#define XBEE_TX        0
#define XBEE_RX        1
#define COMPRESSOR     2
#define FAN            3
#define HEARTBEAT      13
#define BAUD_RATE      9600

uint8_t compressor_state = 0;
uint8_t fan_state        = 0;
bool heartbeat_state     = 0;
uint8_t recipient_id     = 1; // Set this Arduino's recipient ID

void setup() {
  Serial.begin(BAUD_RATE);
  Serial1.begin(BAUD_RATE);
  
  pinMode(COMPRESSOR, OUTPUT);
  pinMode(FAN, OUTPUT);
  pinMode(HEARTBEAT, OUTPUT);
  
  digitalWrite(COMPRESSOR, LOW);
  digitalWrite(FAN, LOW);
}

void loop() {
  // Check if there is data available on the Serial monitor
  if (Serial1.available() > 0) {
    String packet = Serial1.readStringUntil('\n'); // Read the packet until a newline character
    parsePacket(packet);
  }

  digitalWrite(HEARTBEAT, heartbeat_state);
  heartbeat_state = !heartbeat_state;
}

void parsePacket(String packet) {
  // Trim any whitespace and validate packet length
  packet.trim();

  // Example expected packet format: "SENDER_ID,RECIPIENT_ID,COMPRESSOR,FAN"
  int comma1 = packet.indexOf(',');
  int comma2 = packet.indexOf(',', comma1 + 1);
  int comma3 = packet.indexOf(',', comma2 + 1);

  if (comma1 == -1 || comma2 == -1 || comma3 == -1) {
    Serial.println("Invalid packet format.");
    return;
  }

  // Extract each part of the packet
  uint8_t sender_id = packet.substring(0, comma1).toInt();
  uint8_t target_id = packet.substring(comma1 + 1, comma2).toInt();
  uint8_t compressor_cmd = packet.substring(comma2 + 1, comma3).toInt();
  uint8_t fan_cmd = packet.substring(comma3 + 1).toInt();

  // Check if the packet is intended for this Arduino
  if (target_id == recipient_id) {
    // Update states and control outputs
    compressor_state = compressor_cmd;
    fan_state = fan_cmd;

    digitalWrite(COMPRESSOR, compressor_state);
    digitalWrite(FAN, fan_state);

    Serial.print("Packet received from sender ID: ");
    Serial.println(sender_id);
    Serial.print("Compressor state updated to: ");
    Serial.println(compressor_state);
    Serial.print("Fan state updated to: ");
    Serial.println(fan_state);
  } else {
    Serial.println("Packet not intended for this Arduino.");
  }
}
