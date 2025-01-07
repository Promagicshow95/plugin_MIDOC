model GTFSreader

global {
    // Path to the GTFS file
     gtfs_file gtfs_f <- gtfs_file("../includes/tisseo_gtfs_v2");	
	 shape_file boundary_shp <- shape_file("../includes/boundaryTLSE-WGS84PM.shp");

	//shape_file boundary_shp <- shape_file("../includes/boundaryHN.shp");
    //gtfs_file gtfs_f <- gtfs_file("../includes/hanoi_gtfs_am");	


	geometry shape <- envelope(boundary_shp);
//	geometry shape <- envelope(gtfs_f);
	
	
//	geometry shape <- polygon([{0, 20688.512012230232}, {24854.298367634357, 20688.512012230232}, {24854.298367634357, 0}, {0,0}]);
//	geometry shape <- polygon([{0, 116161.06372411549}, {99901.35871416889 ,116161.06372411549}, {99901.35871416889, 0}, {0,0}]);
 
    // Initialization section
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        // Log the boundary envelope by stops
    	write "Boundary envelope: " + shape;
    	
    	// Check envelope of shape file
    	geometry stop_envelope <- envelope(gtfs_f);
    	write "Stop envelope: " + stop_envelope;
        
        // Create bus_stop agents from the GTFS data
       create bus_stop from: gtfs_f  {
       	
				
       }
       
       
       
    }
}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {

    init {
       
       
       if length(departureTripsInfo)> 0 {
       	write "Bus stop initialized: " + stopId + ", " + stopName + ", location: " + location + "," + departureTripsInfo;
       }
 
		
		
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
    
     aspect base {
     	
     	
		draw circle (100.0) at: location color:#blue;	
     }
}

species my_species skills: [TransportStopSkill] {
    // Accès à la liste des arrêts créés
    reflex check_stops {
        write "Nombre d'arrêts créés: " + length(bus_stop);  // Affiche le nombre d'arrêts créés
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
