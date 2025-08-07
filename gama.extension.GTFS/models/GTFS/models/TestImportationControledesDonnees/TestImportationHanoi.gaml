model TestImportationControledesDonnees

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../../includes/hanoi_gtfs_pm");
     
	shape_file boundary_shp <- shape_file("../../includes/shapeFileHanoishp.shp");
	
	geometry shape <- envelope(boundary_shp);
	
    // Initialization section
    init {
   
        // Create bus_stop agents from the GTFS data
       create bus_stop from: gtfs_f  {
			
       }
            
    }
    
 
}

// Species representing each transport stop
species bus_stop skills: [TransportStopSkill] {

     aspect base { 	
		draw circle (100.0) at: location color:#blue;	
     }
}

species my_species skills: [TransportStopSkill] {
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
            // Display the bus_stop agents on the map
            species bus_stop aspect: base;
            
        }
    }
}
