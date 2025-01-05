#define BAUD_RATE 115200

void setup() {
  // Initialize the Serial Monitor
  Serial.begin(BAUD_RATE);
  Serial1.begin(BAUD_RATE);

  // Wait for the Serial Monitor to open
  //while (!Serial) {
  //  ; // Wait for the Serial Monitor to connect. Needed for native USB boards.
  //}
}

void loop() {
  
  // Check if data is available on Serial1
  if (Serial1.available() > 0) {
    // Read a byte from Serial1
    char dataFromSerial = Serial1.read();
    Serial.write(dataFromSerial);
  }
}