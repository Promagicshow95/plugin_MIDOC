model GTFS_Stop_Display

global {
    // Path to the GTFS stops file
    string gtfs_file_path <- "C://Users//tiend//Desktop//Prepared for MIDOC//Prepared for MIDOC//Donnée//DataFile//tisseo_gtfs_v2";

    // Initialization section
    init {
        write "Loading GTFS contents from: " + gtfs_file_path;
        
        // Create a manager agent to handle the loading of GTFS data
        create gtfs_manager number: 1 {
            // Load stops from the GTFS file using the skill
            int outstop <- loadStopsFromGTFS(filePath: gtfs_file_path);
            write "Nombre d'arrêts créés: " + length(stops);

        }
    }
}

// Species representing a manager that loads the GTFS stops
species gtfs_manager skills: [TransportStopSkill] {
    
    // Reflex to display the number of stops created
    reflex check_stops {
        write "Nombre d'arrêts créés: " + length(stops);  // Display the number of stops created
    }
}

// Species representing each transport stop
species bus_stop {
    // Attributes for latitude, longitude, and stop information
    float latitude <- 0.0;
    float longitude <- 0.0;
    string stopId <- "";
    string stopName <- "";

    // Aspect to display each stop
    aspect base {
        draw circle(10) ;  // Display the stop ID as a label
    }
}

// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the bus stops on the map
        display "Bus Stops" {
            // Display the bus_stop agents on the map
            species bus_stop aspect: base;
        }
    }
}
