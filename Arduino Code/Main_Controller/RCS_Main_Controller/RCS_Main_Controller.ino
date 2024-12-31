/**
 *   RCS_IMU_Board_Ctrlr_Algo.ino
 *   Developed by: Shawn Victor
 *   Last Modified: 12-29-2024
 */

// *<-----------------------------------------------------Libraries----------------------------------------------------->*
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_BNO08x.h>
#include <Adafruit_ADS1015.h>
#include "Adafruit_HX711.h"


// *<------------------------------------------------------Macros------------------------------------------------------->*
#define BNO08X_RESET      -1
#define FAST_MODE_ENABLED false
#define ADS_SENSITIVITY   0.1875
#define PITCH_SOL_POS     19 // A5
#define PITCH_SOL_NEG     18 // A4
#define YAW_SOL_POS       4  // D4
#define YAW_SOL_NEG       6  // D6
#define ROLL_SOL_POS      5  // D5
#define ROLL_SOL_NEG      17 // A3
#define LC1_DATA_PIN      2  // D2
#define LC1_SCK_PIN       7  // D7
#define LC2_DATA_PIN      8  // D8
#define LC2_SCK_PIN       9  // D9
#define LC3_DATA_PIN      10 // D10
#define LC3_SCK_PIN       11 // D11
#define LC4_DATA_PIN      12 // D12
#define LC4_SCK_PIN       13 // D13
#define XBEE_TX           0  // D0 (RX)
#define XBEE_RX           1  // D1 (TX)
#define SENDER_ID         0x01

// *<-------------------------------------------------Global Variables------------------------------------------------->*
// Defining BNO085 IMU Objects from Library
Adafruit_BNO08x   IMU(BNO08X_RESET);
sh2_SensorValue_t sensorValue;
sh2_SensorId_t    reportType;

// Defining ADS1015 ADC Objects from Library
Adafruit_ADS1115 ads;
String adc_channel_names[] = {"pt_a003","pt_a009","batt_mon","ads1115_ch4","lc_a016","lc_a017","lc_a018","lc_a019"};
int16_t adc_raw_counts[] = {0,0,0,0,0,0,0,0};

// Defining HX711 ADC Objects from Library
Adafruit_HX711 lc1(LC1_DATA_PIN, LC1_SCK_PIN);
Adafruit_HX711 lc2(LC2_DATA_PIN, LC2_SCK_PIN);
Adafruit_HX711 lc3(LC3_DATA_PIN, LC3_SCK_PIN);
Adafruit_HX711 lc4(LC4_DATA_PIN, LC4_SCK_PIN);

// System State
uint8_t sys_state = 0; // 0 == Manual Mode, 1 == Stabilize
uint8_t valve_states[] = {0,0,0,0,0,0};
uint8_t valve_cmds[] = {0,0,0,0,0,0};

// Stucts
struct quat_t
{
  float r;
  float i;
  float j;
  float k;
};

// IMU Variables
quat_t  sp_quat;
quat_t  pv_quat;
quat_t  err_quat;
unsigned long reportIntervalUs;
unsigned long control_loop_delay_ms = 20;
float   DEADBAND_DEG = 1.0;


// *<-------------------------------------------Helper Functions Declarations------------------------------------------>*
quat_t calcErrorQuat(quat_t*,quat_t*);
quat_t calcQuatConj(quat_t*);
quat_t multiplyQuats(quat_t*,quat_t*);
void   normalizeQuat(quat_t*);
String getJsonString();
void tareHX711();


// *<--------------------------------------------------Setup Functions------------------------------------------------->*
void setup() 
{
  // Serial Monitor Setup
  Serial.begin(115200); // USB Serial for Debugging
  //Serial1.begin(115200); // Hardware Serial for XBEE
  Serial.println("DEBUG: IMU Ctrlr Board Serial Stream Successfully Setup!");

  // Configure Pins
  pinMode(PITCH_SOL_POS,OUTPUT);
  pinMode(PITCH_SOL_NEG,OUTPUT);
  pinMode(YAW_SOL_POS,  OUTPUT);
  pinMode(YAW_SOL_NEG,  OUTPUT);
  pinMode(ROLL_SOL_POS, OUTPUT);
  pinMode(ROLL_SOL_NEG, OUTPUT);
  Serial.println("DEBUG: Solenoid Pins Configured!");
  
  // Configure ADS ADC
  ads.begin();
  Serial.println("DEBUG: ADS1015 ADC Configured!");
  
  // Configure HX711s
  //lc1.begin(); // PINS NOT WORKING
  lc2.begin();
  lc3.begin();
  lc4.begin();
  Serial.println("DEBUG: HX711s Configured!");
  //tareHX711();
  //Serial.println("DEBUG: HX711s Tared!");

  //Attempt to connect to IMU
  bool IMU_isConnected = false;
  while(IMU_isConnected == false)
  {
    IMU_isConnected = IMU.begin_I2C();
    if(IMU_isConnected == false)
    {
      Serial.println("ERROR: Failed to connect to BNO08x IMU Chip.");
      delay(10);
    }
    else
    {
      Serial.println("DEBUG: BNO08x IMU Chip Found!");
    }
  }

  //Configure IMU Objects for Reporting Type / Frequency
  if (FAST_MODE_ENABLED) 
  {
    reportType = SH2_GYRO_INTEGRATED_RV;
    reportIntervalUs = 2000;
  } 
  else 
  {
    reportType = SH2_ARVR_STABILIZED_RV;
    reportIntervalUs = 5000;
  }
  if (! IMU.enableReport(reportType, reportIntervalUs)) 
  {
    Serial.println("ERROR: IMU Reporting Type / Frequency Failed to be Configured!");
  } 
  else
  {
    Serial.println("DEBUG: IMU Reporting Type / Frequency Configured");
  }
  
}


// *<---------------------------------------------------Loop Function-------------------------------------------------->*
void loop() {

  // Request Sensor Event
  bool IMU_Event_Poll_Success = IMU.getSensorEvent(&sensorValue);
  if (IMU_Event_Poll_Success == false)
  {
    Serial.println("WARNING: IMU Event Poll Failure");
    return;
  }
   
  // Update RCS Ctrlr Process Variable Quat
  if(FAST_MODE_ENABLED)
  {
    pv_quat.r = sensorValue.un.gyroIntegratedRV.real;
    pv_quat.i = sensorValue.un.gyroIntegratedRV.i;
    pv_quat.j = sensorValue.un.gyroIntegratedRV.j;
    pv_quat.k = sensorValue.un.gyroIntegratedRV.k;
  }
  else
  {
    pv_quat.r = sensorValue.un.arvrStabilizedRV.real;
    pv_quat.i = sensorValue.un.arvrStabilizedRV.i;
    pv_quat.j = sensorValue.un.arvrStabilizedRV.j;
    pv_quat.k = sensorValue.un.arvrStabilizedRV.k;
  }

  // Read ADC Voltage Values
  adc_raw_counts[0] = ads.readADC_SingleEnded(0);
  adc_raw_counts[1] = ads.readADC_SingleEnded(1);
  adc_raw_counts[2] = ads.readADC_SingleEnded(2);
  adc_raw_counts[3] = ads.readADC_SingleEnded(3);

  // Read HX711 Count Values
  //adc_raw_counts[4] = lc1.readChannelBlocking(CHAN_A_GAIN_128); // PINS NOT WORKING
  adc_raw_counts[5] = lc2.readChannelBlocking(CHAN_A_GAIN_128);
  adc_raw_counts[6] = lc3.readChannelBlocking(CHAN_A_GAIN_128);
  adc_raw_counts[7] = lc4.readChannelBlocking(CHAN_A_GAIN_128);

  // Update RCS Ctrlr Setpoint Quat
  sp_quat.r = 1.0;
  sp_quat.i = 0.0;
  sp_quat.j = 0.0;
  sp_quat.k = 0.0;

  // Print Quat Data to Serial
  
  Serial.println(getJsonString());
  
  // If in the Stabilize State
  if(sys_state == 1)
  {
    // Calculate RCS Ctrlr Error Quat
    err_quat = calcErrorQuat(&pv_quat, &sp_quat);
    normalizeQuat(&err_quat);

    // Check if within Deadband
    float deadband_quat_vmag = sin((DEADBAND_DEG*DEG_TO_RAD)/2);
    float err_quat_v_mag = sqrt(sq(err_quat.i)+sq(err_quat.j)+sq(err_quat.k));
    
    // If not, Perform Control
    if(err_quat_v_mag > deadband_quat_vmag)
    {
        valve_states[0] = err_quat.i > 0;
        valve_states[1] = err_quat.i < 0;
        valve_states[2] = err_quat.j > 0;
        valve_states[3] = err_quat.j < 0;
        valve_states[4] = err_quat.k > 0;
        valve_states[5] = err_quat.k < 0;
    }
    else 
    {
        // Set all valves to be closed if outside of deadband
        for (size_t i = 0; i < 6; i++)
        {
            valve_states[i] = 0;
        }
    }
  }

  // Set all solenoids based on state
  digitalWrite(PITCH_SOL_POS, valve_states[0]);
  digitalWrite(PITCH_SOL_NEG, valve_states[1]);
  digitalWrite(YAW_SOL_POS,   valve_states[2]);
  digitalWrite(YAW_SOL_NEG,   valve_states[3]);
  digitalWrite(ROLL_SOL_POS,  valve_states[4]);
  digitalWrite(ROLL_SOL_NEG,  valve_states[5]);

  // Delay by set amount
  delay(control_loop_delay_ms);
}


// *<-------------------------------------------------Helper Functions------------------------------------------------->*
quat_t calcErrorQuat(quat_t* pv_quat, quat_t* sp_quat)
{
  // Find conjugate of Setpoint
  quat_t pv_quat_conj = calcQuatConj(pv_quat);

  // Find Error Quat by multiplying SP Quat with conjugate of PV Quat
  quat_t err_quat = multiplyQuats(sp_quat, &pv_quat_conj);
  
  return err_quat;
}

quat_t calcQuatConj(quat_t* input_quat)
{
  quat_t resultant_quat;

  resultant_quat.r = input_quat->r;
  resultant_quat.i = -1.0 * (input_quat->i);
  resultant_quat.j = -1.0 * (input_quat->j);
  resultant_quat.k = -1.0 * (input_quat->k);

  return resultant_quat;
}

quat_t multiplyQuats(quat_t* q1, quat_t* q2)
{
  quat_t resultant_quat;

  resultant_quat.r = (q1->r * q2->r) - (q1->i * q2->i) - (q1->j * q2->j) - (q1->k * q2->k);
  resultant_quat.i = (q1->r * q2->i) + (q1->i * q2->r) + (q1->j * q2->k) - (q1->k * q2->j);
  resultant_quat.j = (q1->r * q2->j) + (q1->j * q2->r) + (q1->k * q2->i) - (q1->i * q2->k);
  resultant_quat.k = (q1->r * q2->k) + (q1->k * q2->r) + (q1->i * q2->j) - (q1->j * q2->i);

  return resultant_quat;
}

void normalizeQuat(quat_t* input_quat)
{
  float norm = sqrt(sq(input_quat->r) + sq(input_quat->i) + sq(input_quat->j) + sq(input_quat->k));
  if(norm != 0.0)
  {
    input_quat->r /= norm;
    input_quat->i /= norm;
    input_quat->j /= norm;
    input_quat->k /= norm;
  }
}

void tareHX711()
{
    for (uint8_t t=0; t<3; t++) 
    {
        //lc1.tareA(lc1.readChannelRaw(CHAN_A_GAIN_128));//NOT WORKING
        lc2.tareA(lc2.readChannelRaw(CHAN_A_GAIN_128));
        lc3.tareB(lc3.readChannelRaw(CHAN_B_GAIN_32));
        lc4.tareB(lc4.readChannelRaw(CHAN_B_GAIN_32));
  }
}

String getJsonString()
{
    String serialOutputString = "{";
    String valve_names[]    = {"sv_a010_tkbk","sv_a011_tkbk","sv_a012_tkbk","sv_a013_tkbk","sv_a014_tkbk","sv_a015_tkbk"};

    // Packet Header
    serialOutputString += "\"recipient_id\": " + String("0x00");
    serialOutputString += ", \"sender_id\": " + String("0x02");

    // System Variables
    serialOutputString += ", \"t\": "            + String(millis());
    serialOutputString += ", \"sys_state\": "   + String(sys_state);
    
    // IMU Variables
    serialOutputString += ", \"qx\": "          + String(pv_quat.i, 2);
    serialOutputString += ", \"qy\": "          + String(pv_quat.j, 2);
    serialOutputString += ", \"qz\": "          + String(pv_quat.k, 2);
    serialOutputString += ", \"qw\": "          + String(pv_quat.r, 2);

    // Valve States
    for(int i = 0; i < 6; i++)
    {
        serialOutputString += ", \"" + valve_names[i] + "\": " + String(valve_states[i]);
    }

    // ADC Variables
    for(int i = 0; i < 4; i++)
    {
        serialOutputString += ", \"" + adc_channel_names[i] + "_volts_counts\": " + String(adc_raw_counts[i]);
    }

    // Load Cell Variables
    for(int i = 4; i < 8; i++)
    {
        serialOutputString += ", \"" + adc_channel_names[i] + "_volts_counts\": " + String(adc_raw_counts[i]);
    }

    serialOutputString += "}";
    return serialOutputString;
}
