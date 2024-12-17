/*
 * Cold_Steer_Ctrl_Panel.pde
 * Code by: Shawn Victor
 * Last Modified: 12/3/2024
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
PImage diagram; // Background Diagram
PImage logo;    // Cold Steer Logo

// All Plotted Sensor/Valve Names
String[] all_plotted_sensor_names = new String[] {"pt_a003","pt_a009","lc_a016","lc_a017","lc_a018","lc_a019"};
String[] all_plotted_sensor_desc  = new String[] {"Tank Pressure","Downstream Pressure","Pitch+ Force","Pitch- Force","Yaw+ Force","Yaw- Force"};
String[] all_sv_names             = new String[] {"sv_a010_cmd","sv_a011_cmd","sv_a012_cmd","sv_a013_cmd","sv_a014_cmd","sv_a015_cmd"};

// Data From Uplink Control Board
int sv_a010_state = 0; // P+
int sv_a011_state = 0; // P-
int sv_a012_state = 0; // Y+
int sv_a013_state = 0; // Y-
int sv_a014_state = 0; // R+
int sv_a015_state = 0; // R-
int mv_a008_state = 0; // Pressurization Valve
const float pt_a003_slope = 0.0;    // High Press PT Slope
const float pt_a003_offst = 0.0;    // High Press PT Intercept
float pt_a003_raw = 0.0;            // High Press PT Raw Voltage
const float pt_a009_slope = 0.0;    // Low Press PT Slope
const float pt_a009_offst = 0.0;    // Low Press PT Intercept
float pt_a009_raw = 0.0;            // Low Press PT Raw Voltage
const float lc_a016_slope = 0.0;    // P+ LC Slope
const float lc_a016_offst = 0.0;    // P+ LC Intercept
float lc_a016_raw = 0.0;            // P+ LC Raw Voltage
const float lc_a017_slope = 0.0;    // P- LC Slope
const float lc_a017_offst = 0.0;    // P- LC Intercept
float lc_a017_raw = 0.0;            // P- LC Raw Voltage
const float lc_a018_slope = 0.0;    // Y+ LC Slope
const float lc_a018_offst = 0.0;    // Y+ LC Intercept
float lc_a018_raw = 0.0;            // Y+ LC Raw Voltage
const float lc_a019_slope = 0.0;    // Y- LC Slope
const float lc_a019_offst = 0.0;    // Y- LC Intercept
float lc_a019_raw = 0.0;            // Y- LC Raw Voltage

// Processing Commanding Valve States (to be sent to Uplink)
int sv_a010_cmd = 0;
int sv_a011_cmd = 0;
int sv_a012_cmd = 0;
int sv_a013_cmd = 0;
int sv_a014_cmd = 0;
int sv_a015_cmd = 0;

// Serial Port Settings
Serial serialPort;
String serialPortName = "COM7";
int    baud_rate      = 9600;
byte[] inBuffer       = new byte[100];
int    counter        = 0;

// *<--------------------------------------------------Plot Configs-------------------------------------------------->*
// Settings for Plotter as saved in this file
JSONObject plotterConfigJSON;
String     topSketchPath = "";

// Linegraph Size (For all)
int linegraph_width       = 300;
int linegraph_height      = 175;
int linegraph_buffer_size = 100;

// Linegraph Colors
color GREY    = color(71, 71, 71);
color GREEN   = color(131, 255, 20);
color RED     = color(147, 39, 143);
color PURPLE  = color(160, 32, 240); 
color LED_RED = color(193, 39, 45);

// Plot Positions on Display {X,Y}
int[] pt_a003_plot_pos = {65,50};
int[] pt_a009_plot_pos = {445,50};
int[] lc_a016_plot_pos = {1585,50};
int[] lc_a017_plot_pos = {1205,50};
int[] lc_a018_plot_pos = {825,50};
int[] lc_a019_plot_pos = {65,320};
int[][] all_plot_pos   = new int[][] {pt_a003_plot_pos,pt_a009_plot_pos,lc_a016_plot_pos,lc_a017_plot_pos,lc_a018_plot_pos,lc_a019_plot_pos};

// SV LED Positions on Display {X,Y}
int[] sv_a010_led_pos  = {980,300};
int[] sv_a011_led_pos  = {980,300};
int[] sv_a012_led_pos  = {980,300};
int[] sv_a013_led_pos  = {980,300};
int[] sv_a014_led_pos  = {980,300};
int[] sv_a015_led_pos  = {980,300};
int[][] all_sv_led_pos = new int[][] {sv_a010_led_pos,sv_a011_led_pos,sv_a012_led_pos,sv_a013_led_pos,sv_a014_led_pos,sv_a015_led_pos}; 

// MV LED Positions on Display {X,Y}

// Line Graph Variables
Graph  pt_a003_plot  = new Graph(pt_a003_plot_pos[0], pt_a003_plot_pos[1], linegraph_width, linegraph_height, GREY);
Graph  pt_a009_plot  = new Graph(pt_a009_plot_pos[0], pt_a009_plot_pos[1], linegraph_width, linegraph_height, GREY);
Graph  lc_a016_plot  = new Graph(lc_a016_plot_pos[0], lc_a016_plot_pos[1], linegraph_width, linegraph_height, GREY);
Graph  lc_a017_plot  = new Graph(lc_a017_plot_pos[0], lc_a017_plot_pos[1], linegraph_width, linegraph_height, GREY);
Graph  lc_a018_plot  = new Graph(lc_a018_plot_pos[0], lc_a018_plot_pos[1], linegraph_width, linegraph_height, GREY);
Graph  lc_a019_plot  = new Graph(lc_a019_plot_pos[0], lc_a019_plot_pos[1], linegraph_width, linegraph_height, GREY);
Graph[]    all_plot  = new Graph[] {pt_a003_plot,pt_a009_plot,lc_a016_plot,lc_a017_plot,lc_a018_plot,lc_a019_plot};

// Data Matrix for each LineGraph (rows are for each line graph within the single graph, columns are the datapoints)
float[][] pt_a003_plot_values = new float[1][linegraph_buffer_size];
float[][] pt_a009_plot_values = new float[1][linegraph_buffer_size];
float[][] lc_a016_plot_values = new float[1][linegraph_buffer_size];
float[][] lc_a017_plot_values = new float[1][linegraph_buffer_size];
float[][] lc_a018_plot_values = new float[1][linegraph_buffer_size];
float[][] lc_a019_plot_values = new float[1][linegraph_buffer_size];


// *<---------------------------------------------------Setup Code--------------------------------------------------->*
void setup()
{
    System.out.println("*STARTING SETUP*");

    // Load in Supporting Images
    diagram = loadImage("Cold_Steer_Control_Panel.jpg");
    logo    = loadImage("Cold_Steer_Logo.jpg");

    // Configure Window / Background
    frame.setTitle("Cold_Steer_Control_Panel"); //Set Window Name
    size(1905,1000); // Set Window Resolution
    background(30);  // Set Background Color to Greyscale 30 (Dark Grey)
    image(diagram, 387, 285); // Loads in Diagram at set x,y location
    image(logo, 0, 835); // Loads in Logo at set x,y location

    // Get Local File Paths
    topSketchPath      = sketchPath();
    plotterConfigJSON  = loadJSONObject(topSketchPath + "/plotter_config.json");

    // Setup Control P5
    cp5 = new ControlP5(this);

    // Begin Serial Communications
    serialPort = new Serial(this, serialPortName, baud_rate);

    // Create Min/Max Range Limits for Each Plot:
    counter = 0;
    for(int[] plot_pos: all_plot_pos)
    {
        String sensor_plot_name = all_plotted_sensor_names[counter];
        cp5.addTextfield(sensor_plot_name+"mx").setPosition(plot_pos[0]-55, plot_pos[1]-30).setText(getPlotterConfigString(sensor_plot_name+"mx")).setWidth(40).setAutoClear(false);
        cp5.addTextfield(sensor_plot_name+"mn").setPosition(plot_pos[0]-55, plot_pos[1]+190).setText(getPlotterConfigString(sensor_plot_name+"mn")).setWidth(40).setAutoClear(false);
        counter++;
    }   

    // Create CMD sliders for Each SV:
    counter = 0;
    for(int[] sv_led_pos: all_sv_led_pos)
    {
        String sv_toggle_name = all_sv_names[counter];
        cp5.addToggle(sv_toggle_name).setPosition(sv_led_pos[0]-45, sv_led_pos[1]+30).setValue(0).setMode(ControlP5.SWITCH).setColorActive(color(193, 39, 45));
        counter++;
    }

    // Configure each Plot
    counter = 0;
    for(Graph plot: all_plot)
    {
        plot.Title          = all_plotted_sensor_desc[counter];
        plot.xDiv           = 7;
        plot.yDiv           = 0;
        plot.linegraph.yMax = int(getPlotterConfigString(all_plotted_sensor_names[counter]+"mx"));
        plot.linegraph.yMin = int(getPlotterConfigString(all_plotted_sensor_names[counter]+"mn"));
        plot.xLabel = " Time(sec) ";

        // Set Y-Label based on Sensor Name Prefix
        sensor_prefix = all_plotted_sensor_names[counter].substring(0,2);
        switch(sensor_prefix)
        {
            case "pt":
                plot.ylabel = "Pressure (psia)";
                break;
            case "lc":
                plot.ylabel = "Force (lbf)";
                break;
            default:
                plot.ylabel = "Sensor Prefix Unknown?"
                break;
        }

        counter++;
    }

    System.out.println("*SETUP COMPLETED*");
}

// *<--------------------------------------------------Looped Code--------------------------------------------------->*
void draw()
{
    // Attempt to get new Data and covert it to String Format
    try {serialPort.readBytesUntil('\n', inBuffer)}
    catch(Exception e) {System.out.println("No new data found in the COM Port");}
    String bufferData = new String(inBuffer);


}

// *<----------------------------------------------Supporting Functions---------------------------------------------->*
// Get GUI Settings from Settings File
String getPlotterConfigString(String id) 
{
  String r = "";
  try {
    r = plotterConfigJSON.getString(id);
  } 
  catch (Exception e) {
    r = "";
  }
  return r;
}