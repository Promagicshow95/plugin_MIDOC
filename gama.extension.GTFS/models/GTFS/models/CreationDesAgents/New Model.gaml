model GTFSreader

global {
    // Path to the GTFS file
     gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");	
	 shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
	 string formatted_time;

	date starting_date <- date("2024-02-21T20:55:00");


	geometry shape <- envelope(boundary_shp);

	

    // Initialization section
    init {
       
    	// Check envelope of shape file
    	geometry stop_envelope <- envelope(gtfs_f);
    	//write "Stop envelope: " + stop_envelope;
        
        // Create bus_stop agents from the GTFS data
       create bus_stop from: gtfs_f  {
       	
				
       }
       
       do export_bus_stop_json;

       
    }
    
 	action export_bus_stop_json {
    list<bus_stop> filtered_stops <- bus_stop where (length(each.departureStopsInfo) > 0 and each.routeType = 3);
    string json_out <- to_json(filtered_stops);
    file f <- file("../../includes/bus_stops_filtered.txt");
    save  f;
    write "complete";
	}
 	
}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {
	
  action customInit  {
    	if (length(departureStopsInfo))> 0 and (routeType =3) {
       		
       }

		
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
        
            
        }
    }
}
