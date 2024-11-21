model TransportTripSkill

global {
    // Path to the GTFS file
    gtfs_file hanoi_gtfs <- gtfs_file("../includes/tisseo_gtfs_v2");
    
    // Initialization section
    init {
        write "Loading GTFS contents from: " + hanoi_gtfs;
        
        // Create bus_stop agents from the GTFS data
       create bus_trip from: hanoi_gtfs  {
				
       }
    }
}
 
// Species representing each transport stop
species bus_trip skills: [TransportTripSkill] {
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
    
     aspect base {
     	draw circle(1) color: #blue;
     }
}

species my_species skills: [TransportTripSkill] {
    // Accès à la liste des arrêts créés
    reflex check_stops {
        write "Nombre d'arrêts créés: " + length(bus_trip);  // Affiche le nombre d'arrêts créés
    }
    aspect base {}
}

// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the bus stops on the map
        display "Bus Stops" {
            // Display the bus_stop agents on the map
            species bus_trip aspect: base;
            species my_species aspect:base;
            
        }
    }
}
