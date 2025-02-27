model TransportTripSkill

global {
    // Path to the GTFS file
    gtfs_file hanoi_gtfs <- gtfs_file("../../includes/tisseo_gtfs_v2");
    shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
    
    geometry shape <- envelope(boundary_shp);
    
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
	init {
        write "Bus trip initialized: " + tripId + ", " + stopsInOrder;
    }
    
     aspect base {
		draw circle (100.0)  color:#blue;	
     }
}

species my_species skills: [TransportTripSkill] {
    // Accès à la liste des arrêts créés
    reflex check_trips {
        write "Nombre des trips créés: " + length(bus_trip);  // Affiche le nombre d'arrêts créés
    }
    aspect base {
    	draw circle (100.0)  color:#blue;
    }
}

// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the bus stops on the map
        display "Bus Trips" {
            // Display the bus_stop agents on the map
            species bus_trip aspect: base;
            species my_species aspect:base;
            
        }
    }
}
