#include <Arduino.h>
String fullVolt, Vstring1, Vstring2, espacio = " ";

void setup() {
  pinMode(15, INPUT);
  pinMode(4, INPUT);
  Serial.begin(115200);
}

void loop() {
  float volt1=(analogRead(15))*(3.3/4095);
  float volt2=(analogRead(4))*(3.3/4095);
  Vstring1 = String(volt1);
  Vstring2 = String(volt2);

  fullVolt = Vstring1 + espacio + Vstring2;
  Serial.println(fullVolt);
  delay(1);
}