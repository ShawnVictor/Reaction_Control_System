using System.IO.Ports;
using System.Threading;
using UnityEngine;
using System.Collections.Generic;

public class Controller : MonoBehaviour
{
    public static string portName = "COM18";
    public static int baudRate = 115200;
    private static string buffer = ""; // Buffer to accumulate data
    private static SerialPort serialPort;
    private static bool firstDataReceived = true;  // Flag to check if this is the first data packet


    Thread serialThread = new Thread(ReadSerialPort);

    [System.Serializable]
    public class QuaternionData
    {
        public float qx;
        public float qy;
        public float qz;
        public float qw;
    }

    public static bool newQuatFlag = false;
    public Transform targetObject; // The GameObject to update with the quaternion data
    private static Quaternion latestQuaternion = Quaternion.identity; // Store the latest quaternion
    private readonly object lockObject = new object(); // Lock for thread safety

   void Start()
    {
        // Explicitly set the object's rotation to zero (identity quaternion) at the start
        targetObject.rotation = Quaternion.identity;  // Ensures no rotation
        Debug.Log("Initial rotation set to identity (standing straight up).");

        // Start the serial communication thread
        serialThread.Start();
    }

    void Update()
    {
        if (newQuatFlag)
        {
            // Apply Quaternion Rotation to targetObject
            Debug.Log($"Applying Rotation: Quaternion({latestQuaternion.x}, {latestQuaternion.y}, {latestQuaternion.z}, {latestQuaternion.w})");
            targetObject.rotation = latestQuaternion;
            Debug.Log($"Applied Rotation (Euler): {targetObject.rotation.eulerAngles}");
            newQuatFlag = false;
        }
    }

    private static void ReadSerialPort()
    {
        serialPort = new SerialPort(portName, baudRate);
        serialPort.Open();

        while (true)
        {
            string incomingData = serialPort.ReadExisting();
            if (!string.IsNullOrEmpty(incomingData))
            {
                buffer += incomingData; // Append new data to the buffer

                // Process complete lines (JSON objects)
                int newlineIndex;
                while ((newlineIndex = buffer.IndexOf('\n')) >= 0)
                {
                    string completeJson = buffer.Substring(0, newlineIndex).Trim();
                    buffer = buffer.Substring(newlineIndex + 1); // Remove processed line

                    try
                    {
                        // Manually extract quaternion data
                        float qx = ExtractValueFromJson(completeJson, "1");
                        float qy = ExtractValueFromJson(completeJson, "2");
                        float qz = ExtractValueFromJson(completeJson, "3");
                        float qw = ExtractValueFromJson(completeJson, "4");

                        // If we successfully extracted all four components
                        if (!float.IsNaN(qx) && !float.IsNaN(qy) && !float.IsNaN(qz) && !float.IsNaN(qw))
                        {
                            // Zero the quaternion on first data receive
                            if (firstDataReceived)
                            {
                                latestQuaternion = Quaternion.identity;  // Set to zero quaternion
                                firstDataReceived = false;  // Disable zeroing after the first packet
                                Debug.Log("First data received, quaternion set to zero.");
                            }

                            // Map the extracted values to the QuaternionData
                            QuaternionData quaternionData = new QuaternionData
                            {
                                qx = qx,
                                qy = qy,
                                qz = qz,
                                qw = qw
                            };

                            // Axis remapping to match Unity's coordinate system
                            latestQuaternion = new Quaternion(quaternionData.qx, -quaternionData.qz, quaternionData.qy, quaternionData.qw);
                            newQuatFlag = true;
                            Debug.Log($"Parsed Quaternion: qx={quaternionData.qx}, qy={quaternionData.qy}, qz={quaternionData.qz}, qw={quaternionData.qw}");
                        }
                    }
                    catch (System.Exception ex)
                    {
                        Debug.LogWarning($"Failed to parse JSON manually: {ex.Message}");
                    }
                }
            }

            Thread.Sleep(50); // Adjust as necessary
        }
    }

    // Helper function to extract a value from the JSON string
    private static float ExtractValueFromJson(string json, string key)
    {
        string searchKey = $"\"{key}\":";
        int keyIndex = json.IndexOf(searchKey);

        if (keyIndex >= 0)
        {
            int startIndex = keyIndex + searchKey.Length;
            int endIndex = json.IndexOf(',', startIndex);
            if (endIndex == -1)
            {
                endIndex = json.IndexOf('}', startIndex); // Handle the case where it's the last item
            }

            string valueString = json.Substring(startIndex, endIndex - startIndex).Trim();
            
            if (float.TryParse(valueString, out float value))
            {
                return value;
            }
        }

        return float.NaN; // Return NaN if the key was not found or parsing failed
    }

    private void OnDestroy()
    {
        serialThread.Abort();
        serialPort.Close();
    }
}