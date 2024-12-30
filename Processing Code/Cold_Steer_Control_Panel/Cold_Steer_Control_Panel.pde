/*
 * Cold_Steer_Ctrl_Panel.pde
 * Code by: Shawn Victor
 * Last Modified: 12/21/2024
 */


//Importing Libraries
import java.awt.Frame;
import java.awt.BorderLayout;
import javax.swing.JLabel;
import javax.swing.ImageIcon;
import controlP5.*;
import processing.serial.*;

// *<-------------------------------------------------Global Variables------------------------------------------------->*
// Control Panel Variables
ControlP5 cp5;  // Used to control all ControlP5 Variables
PImage diagram, logo; // Background Diagram, Cold Steer Logo

// JSON Variables for getting System Config
JSONObject config;
JSONObject plot_settings;
JSONArray sensors, valves;

// Data From Uplink Control Board
int[] valve_states;
float[] sensor_raw_values;
float[] sensor_scaled_values;

// Processing Commanding Valve States (to be sent to Uplink)
int[] valve_cmds;

// Watchdog variables
long[] lastUpdateTimes;  // Timestamps of the last received packet from each node
int[] nodeStates;        // States for each node (1: Active, 0: Inactive)
JSONArray nodes;        // JSON array of nodes

// Serial Port Settings
Serial serialPort;

// Sample Data
float[]   linegraph_sample = new float[100];

// *<--------------------------------------------------Plot Configs-------------------------------------------------->*
// Settings for Plotter as saved in this file
JSONObject plotterConfigJSON;
String     topSketchPath = "";

// Line Graph Variables
int linegraph_width;
int linegraph_height;
int linegraph_buffer_size;
int linegraph_x_div;
int linegraph_y_div;
JSONObject color_swatch;
Graph[] all_plots;
int[] plot_color;

// Data Matrix for each LineGraph (rows are for each line graph within the single graph, columns are the datapoints)
float[][] sensor_plot_values;


// *<---------------------------------------------------Setup Code--------------------------------------------------->*
void setup()
{
    System.out.println("DEBUG: STARTING SETUP!");

    // Load in Supporting Images
    //diagram = loadImage("Cold_Steer_Control_Panel.jpg");
    //logo    = loadImage("Cold_Steer_Logo.jpg");
    diagram = loadImage("LRA_P&ID.jpg");
    logo    = loadImage("Quasar Logo.jpg");
    System.out.println("DEBUG: Image & Diagram Loaded!");

    // Load in System Configuration
    topSketchPath      = sketchPath();
    plotterConfigJSON  = loadJSONObject(topSketchPath + "/plotter_config.json");
    config = loadJSONObject(topSketchPath + "/sys_config.json");
    try
    {
      sensors = config.getJSONArray("sensors");
      valves = config.getJSONArray("valves");
      plot_settings = config.getJSONObject("plot_settings");
      System.out.println("DEBUG: Configs Loaded Successfully!");
    }
    catch (Exception e){System.out.println(("ERROR: Failed to load configs: " + e.getMessage()));}
    
    // Load in Const Plot Settings
    linegraph_width       = plot_settings.getInt("linegraph_width");
    System.out.println("DEBUG: w!");
    linegraph_height      = plot_settings.getInt("linegraph_height");
    System.out.println("DEBUG: h!");
    linegraph_buffer_size = plot_settings.getInt("linegraph_buffer_size");
    System.out.println("DEBUG: buff!");
    linegraph_x_div       = plot_settings.getInt("linegraph_x_div");
    System.out.println("DEBUG: xdiv!");
    linegraph_y_div       = plot_settings.getInt("linegraph_y_div");
    System.out.println("DEBUG: ydiv!");
    color_swatch          = plot_settings.getJSONObject("colors");
    System.out.println("DEBUG: Plot Settings Configured!");

    // Initialize Variables
    valve_cmds   = new int[valves.size()];
    valve_states = new int[valves.size()];
    sensor_raw_values = new float[sensors.size()];
    sensor_scaled_values = new float[sensors.size()];
    all_plots = new Graph[sensors.size()];
    sensor_plot_values = new float[sensors.size()][linegraph_buffer_size];
    System.out.println("DEBUG: Variables Initialized!");

    // Initialize watchdog variables
    nodes = config.getJSONArray("nodes");
    lastUpdateTimes = new long[nodes.size()];
    nodeStates = new int[nodes.size()];
    for (int i = 0; i < nodes.size(); i++) {
        lastUpdateTimes[i] = millis();  // Set initial time
        nodeStates[i] = 0;              // Assume all nodes are active initially
    }
    System.out.println("DEBUG: Watchdogs Initialized!");

    // Configure Window / Background
    surface.setTitle("Cold_Steer_Control_Panel"); //Set Window Name
    size(1905,1000); // Set Window Resolution
    background(30);  // Set Background Color to Greyscale 30 (Dark Grey)
    image(diagram, 387, 285); // Loads in Diagram at set x,y location
    image(logo, 0, 835); // Loads in Logo at set x,y location
    System.out.println("DEBUG: Window/Background Configured!");

    // Setup Control P5
    cp5 = new ControlP5(this);

    // Begin Serial Communications
    JSONObject serialConfig = config.getJSONObject("serial");
    try
    {
      serialPort = new Serial(this, serialConfig.getString("port"), serialConfig.getInt("baud_rate"));
      System.out.println("DEBUG: Sucessful Connection to : " + serialConfig.getString("port") + " @ BAUD: " + serialConfig.getInt("baud_rate"));
    }
    catch (Exception e){System.out.println(("ERROR: Failed to establish Serial Connection on : " + serialConfig.getString("port")));}

    // Configure Sensors
    for (int i = 0; i < sensors.size(); i++) 
    {
        JSONObject sensor = sensors.getJSONObject(i);
        
        if(!sensor.getBoolean("enabled")){continue;}  // Skip if not enabled

        String name = sensor.getString("name");
        int[] pos = sensor.getJSONArray("position").getIntArray();
        int[] plot_color = color_swatch.getJSONArray(sensor.getString("color")).getIntArray();

        // Configure each Plot
        all_plots[i]        = new Graph(pos[0], pos[1], linegraph_width, linegraph_height, color(plot_color[0], plot_color[1], plot_color[2]));
        all_plots[i].xLabel = " Time(sec) ";
        all_plots[i].yLabel = sensor.getString("unit");
        all_plots[i].Title  = name + ": " + sensor.getString("desc");
        all_plots[i].xDiv   = plot_settings.getInt("linegraph_x_div");
        all_plots[i].yDiv   = plot_settings.getInt("linegraph_y_div");
        all_plots[i].yMin   = sensor.getInt("y_min");
        all_plots[i].yMax   = sensor.getInt("y_max");
        all_plots[i].GraphColor = color(plot_color[0], plot_color[1], plot_color[2]);


        // Example: Create text fields for min/max values
        cp5.addTextfield(name + "_mx")
            .setPosition(pos[0] - 55, pos[1] - 30)
            .setText(String.valueOf(all_plots[i].yMax))
            .setWidth(40)
            .setAutoClear(false);
        cp5.addTextfield(name + "mn")
            .setPosition(pos[0] - 55, pos[1] + 190)
            .setText(String.valueOf(all_plots[i].yMin))
            .setWidth(40)
            .setAutoClear(false);
       System.out.println("DEBUG: Successfully Configured sensor: " + name);
    }

    // Configure Valves
    for (int i = 0; i < valves.size(); i++)
    {
        JSONObject valve = valves.getJSONObject(i);

        if(!valve.getBoolean("enabled")){continue;}  // Skip if not enabled

        String name   = valve.getString("name");
        int[] pos     = valve.getJSONArray("position").getIntArray();
        int[] led_pos = valve.getJSONArray("led_pos").getIntArray();
        int[] green_led_color = color_swatch.getJSONArray("LED_GREEN").getIntArray();

        // Create toggle for each valve
        cp5.addToggle(name)
            .setPosition(pos[0], pos[1])
            .setValue(0)
            .setMode(ControlP5.SWITCH)
            .setColorActive(color(193, 39, 45));

        // Create Status LEDs
        fill(color(green_led_color[0], green_led_color[1], green_led_color[2]));
        stroke(225);
        strokeWeight(1);
        circle(led_pos[0], led_pos[1], 15);
        System.out.println("DEBUG: Successfully Configured valve: " + name);
    }

    System.out.println("DEBUG: SETUP COMPLETED!");
}

// *<--------------------------------------------------Looped Code--------------------------------------------------->*
void draw()
{
    // Attempt to get new Data and covert it to String Format
    JSONObject dataPacket_JSON_Obj = null;
    byte[] inBuffer = serialPort.readBytesUntil('\n');
    if (inBuffer != null && inBuffer.length > 0)
    {
        // Convert the inBuffer to a String & Parse
        String bufferData = new String(inBuffer).trim();
        dataPacket_JSON_Obj = parseIncomingData(bufferData);
    } 

    // Check if the packet is valid and for the Ground Controller
    if (dataPacket_JSON_Obj == null){return;}

    // Verify recipient ID
    checkIfPacketIsForMe(dataPacket_JSON_Obj);

    // Update States & Values
    UpdateWatchdogStates(dataPacket_JSON_Obj);
    UpdateSensorValues(dataPacket_JSON_Obj);
    UpdateSensorValueTable();
    UpdateValveStates(dataPacket_JSON_Obj);

    //Update Visuals
    UpdateWatchdogVisuals();
    UpdateSensorVisuals();
    UpdateValveVisuals();

    // Read Valve Toggle Switches, Send Command Packets out through the Serial Line

}

// *<----------------------------------------------Supporting Functions---------------------------------------------->*
// Get GUI Settings from Settings File
String getPlotterConfigString(String id) {
    try 
    {
        return config.getString(id);
    } 
    catch (Exception e) 
    {
        return "";
    }
}


// Parse Incoming Data Packet and Update Values
JSONObject parseIncomingData(String dataPacket)
{
    // Parse the incoming JSON String & Check for errors
    try {
        return parseJSONObject(dataPacket);
    } catch (Exception e) {
        println("Invalid JSON packet: " + e.getMessage());
        return null;
    }
}


boolean checkIfPacketIsForMe(JSONObject dataPacket_JSON_Obj)
{
    String recipientId = dataPacket_JSON_Obj.getString("recipient_id");
    if(!recipientId.equals(config.getJSONObject("serial").getString("node_id")))
    {
        println("Packet not intended for this node.");
        return false;
    }
    if (!dataPacket_JSON_Obj.hasKey("recipient_id") || !dataPacket_JSON_Obj.hasKey("sender_id")) 
    {
        println("Missing required keys in JSON packet.");
        return false;
    }
    return true;
}


void UpdateWatchdogStates(JSONObject dataPacket_JSON_Obj)
{
    String senderId = dataPacket_JSON_Obj.getString("sender_id");
    for(int i = 0; i < nodes.size(); i++)
    {
        JSONObject node = nodes.getJSONObject(i);
        if (!node.getBoolean("enabled")) continue;  // Skip if not enabled

        // Check if this noded is defined in the packet structure
        if(node.getString("sender_id").equals(senderId))
        {
            lastUpdateTimes[i] = millis();  // Update the last received time
            nodeStates[i] = 1;              // Mark node as active
        }
    }
}


void UpdateSensorValues(JSONObject dataPacket_JSON_Obj)
{
    for(int i = 0; i < sensors.size(); i++)
    {
        JSONObject sensor = sensors.getJSONObject(i);
        if (!sensor.getBoolean("enabled")) continue;  // Skip if not enabled
        
        // Check if this sensor is found in the datapacket
        String sensorName = sensor.getString("name");
        if(dataPacket_JSON_Obj.hasKey(sensorName))
        {
            // Apply the slope and offset to the raw value
            sensor_raw_values[i] = dataPacket_JSON_Obj.getFloat(sensorName);
            sensor_scaled_values[i] = sensor_raw_values[i] * sensor.getFloat("slope") + sensor.getFloat("offset");
        }
    }
}

void UpdateSensorValueTable()
{
  // Shift all data to the left
  for(int row = 0; row < sensors.size(); row++)
  {
    for(int col = 0; col < sensor_plot_values[row].length-1; col++)
    {
      sensor_plot_values[row][col] = sensor_plot_values[row][col+1]; 
    }
  }
  
  // Insert new data
  for(int row = 0; row < sensors.size(); row++)
  {
    int last_index = sensor_plot_values[row].length-1;
    sensor_plot_values[row][last_index] = sensor_scaled_values[row];
  }
  
}


void UpdateValveStates(JSONObject dataPacket_JSON_Obj)
{
    for(int i = 0; i < valves.size(); i++)
    {
        JSONObject valve = valves.getJSONObject(i);
        if (!valve.getBoolean("enabled")) continue;  // Skip if not enabled

        // Check if this valve is defined in the packet structure
        String valveName = valve.getString("name");
        if(dataPacket_JSON_Obj.hasKey(valveName))
        {
            valve_states[i] = dataPacket_JSON_Obj.getInt(valveName);
        }
    }
}


void updateLED(int[] ledPos, String colorKey) 
{
    JSONArray colorArray = color_swatch.getJSONArray(colorKey);
    int[] ledColor = {colorArray.getInt(0), colorArray.getInt(1), colorArray.getInt(2)};
    fill(colorArray.getInt(0), colorArray.getInt(1), colorArray.getInt(2));
    circle(ledPos[0], ledPos[1], 15);
}


void UpdateWatchdogVisuals()
{
    // Update Watchdogs Visuals
    for (int i = 0; i < nodes.size(); i++)
    {
        long currentTime = millis();
        JSONObject node = nodes.getJSONObject(i);
        int[] led_pos = node.getJSONArray("led_pos").getIntArray();
        if (!node.getBoolean("enabled")) continue;  // Skip if not enabled

        // Check if node is inactive
        int timeout = node.getInt("timeout_ms");
        if(currentTime - lastUpdateTimes[i] > timeout)
        {
            nodeStates[i] = 0;
        }

        // Update Watchdog LEDs
        updateLED(led_pos, valve_states[i] == 1 ? "LED_GREEN" : "LED_RED");
    }
}


void UpdateSensorVisuals()
{
    for(int i = 0; i < all_plots.length; i++)
    {
        // Update The Plot (if applicable)
        JSONObject sensor = sensors.getJSONObject(i);
        if (all_plots[i] != null && sensor.getBoolean("enabled")) 
        {
            all_plots[i].LineGraph(linegraph_sample, sensor_plot_values[i]);
            //Update Sensor Box Values
        }
    }
}


void UpdateValveVisuals()
{
    for (int i = 0; i < valves.size(); i++)
    {
        JSONObject valve = valves.getJSONObject(i);
        int[] led_pos = valve.getJSONArray("led_pos").getIntArray();
        if (!valve.getBoolean("enabled")) continue;  // Skip if not enabled

        // Update Valve Talkbacks
        updateLED(led_pos, valve_states[i] == 1 ? "LED_GREEN" : "LED_RED");
    }
}
