model GTFSreader

global {
    // Path to the GTFS file
    gtfs_file hanoi_gtfs <- gtfs_file("../includes/tisseo_gtfs_v2");
    
    // Initialization section
    init {
        write "Loading GTFS contents from: " + hanoi_gtfs;
        
        // Create bus_stop agents from the GTFS data
       create bus_stop from: hanoi_gtfs  {
       	
				
       }
       
       
       
    }
}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {

    init {
        write "Bus stop initialized: " + stopId + ", " + stopName + ", location: " + location;
    }
    // Attributes for latitude and longitude
//    float latitude <- 0.0;
//    float longitude <- 0.0;
//		--> in the location attribute

//    string stopId <- "";
//    string stopName <- "";
//		--> built-in attributes from the skill



    // Initialization of the stop's attributes
//    init {
//        latitude <- attribute("latitude");
//        longitude <- attribute("longitude");
//        stopId <- attribute("stopId");
//        stopName <- attribute("stopName");
//    }
    
     aspect base {}
}

species my_species skills: [TransportStopSkill] {
    // Accès à la liste des arrêts créés
    reflex check_stops {
        write "Nombre d'arrêts créés: " + length(bus_stop);  // Affiche le nombre d'arrêts créés
    }
    aspect base {
    	draw circle (1.0) at: location;
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
            species my_species aspect:base;
            
        }
    }
}
