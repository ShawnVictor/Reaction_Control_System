#define BAUD_RATE 115200

void setup() {
  // Initialize USB Serial and Serial1
  Serial.begin(BAUD_RATE);    // USB Serial for PC communication
  Serial1.begin(BAUD_RATE);   // Serial1 for XBee communication

  // Wait for Serial Monitor to open (optional, useful for debugging)
  while (!Serial) {
    ; // Do nothing, just wait
  }
}

void loop() {
  // Check if data is available on USB Serial
  if (Serial.available() > 0) 
  {
    // Read incoming data from Serial
    char incomingByte = Serial.read();

    // Send the data to Serial1
    Serial1.write(incomingByte);
  }
}