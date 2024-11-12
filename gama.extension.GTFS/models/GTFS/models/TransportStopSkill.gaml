model TransportStopKill

global {
    // Path to the GTFS file
    gtfs_file hanoi_gtfs <- gtfs_file("../includes/hanoi_gtfs_am");
    
    // Initialization section
    init {
        write "Loading GTFS contents from: " + hanoi_gtfs;
        
        // Create bus_stop agents from the GTFS data
        create bus_stop number: length(hanoi_gtfs.stops) {
            // Use the TransportStopSkill to load stops from the GTFS file
            do loadStopsFromGTFS filePath: hanoi_gtfs;
        }
        create bus_stop number: length(hanoi_gtfs.stops) {
            myfile <- "../includes/hanoi_gtfs_am";
        }
    }
}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {
    // Attributes for latitude and longitude
    float latitude <- 0.0;
    float longitude <- 0.0;
    string stopId <- "";
    string stopName <- "";

    // Geometry based on latitude and longitude (for display on map)
    geometry shape <- point(longitude, latitude);

    // Initialization of the stop's attributes
    init {
        latitude <- attribute("latitude");
        longitude <- attribute("longitude");
        stopId <- attribute("stopId");
        stopName <- attribute("stopName");
    }
    
    as
}

// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the bus stops on the map
        display "Bus Stops" {
            // Display the bus_stop agents on the map
            species bus_stop aspect: [ 
                draw shape color: #blue label: stopName;  // Draw bus stops as blue points with stop names
            ];
        }
    }
}

