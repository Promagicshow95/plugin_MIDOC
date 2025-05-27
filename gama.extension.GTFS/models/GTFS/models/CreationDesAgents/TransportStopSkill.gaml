model GTFSreader

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
     
	shape_file boundary_shp <- shape_file("../../includes/stops_points_wgs84.shp");
	
	geometry shape <- envelope(boundary_shp);
	 //string formatted_time;

	//date starting_date <- date("2024-12-15T20:55:00");

	
	
    // Initialization section
    init {
      
  	
        
        // Create bus_stop agents from the GTFS data
       create bus_stop from: gtfs_f  {
       	
				
       }
       
       ask bus_stop{ do customInit;}
       
       
       
 
       
    }
    
 
}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {
	
  action customInit  {
    	if length(departureStopsInfo)> 0 {
       		//write "Bus stop initialized: " + stopId + ", " + stopName + ", location: " + location + ", departureStopsInfo: " + departureStopsInfo;
       }

		
    }
 
     aspect base {
     	
     	
		draw circle (100.0) at: location color:#blue;	
     }
}

species my_species skills: [TransportStopSkill] {
    // Accès à la liste des arrêts créés
    reflex check_stops {
        //write "Nombre d'arrêts créés: " + length(bus_stop);  // Affiche le nombre d'arrêts créés
    }
    aspect base {
    	draw circle (100.0) at: location color:#blue;
    }
}

// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the bus stops on the map
        display "Bus Stops And Envelope" {
        	// Draw boundary envelope
            
            // Display the bus_stop agents on the map
            species bus_stop aspect: base;
            species my_species aspect:base;
            
        }
    }
}
