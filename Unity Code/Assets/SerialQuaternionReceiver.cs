using System.IO.Ports;
using System.Threading;
using UnityEngine;

public class Controller : MonoBehaviour
{
    public static string portName = "COM6";
    public static int baudRate = 9600;
    private static string buffer = ""; // Buffer to accumulate data
    private static SerialPort serialPort;

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
                        // Parse JSON and store the quaternion
                        QuaternionData quaternionData = JsonUtility.FromJson<QuaternionData>(completeJson);
                        if (quaternionData != null)
                        {
                            // Axis remapping to match Unity's coordinate system
                            latestQuaternion = new Quaternion(quaternionData.qx, -quaternionData.qz, quaternionData.qy, quaternionData.qw);
                            newQuatFlag = true;
                            Debug.Log($"Parsed Quaternion: qx={quaternionData.qx}, qy={quaternionData.qy}, qz={quaternionData.qz}, qw={quaternionData.qw}");
                        }
                    }
                    catch (System.Exception ex)
                    {
                        Debug.LogWarning($"Failed to parse JSON: {ex.Message}");
                    }
                }
            }

            Thread.Sleep(50); // Adjust as necessary
        }
    }

    private void OnDestroy()
    {
        serialThread.Abort();
        serialPort.Close();
    }
}