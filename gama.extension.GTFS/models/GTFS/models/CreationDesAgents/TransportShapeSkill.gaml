model GTFSreader

global  {
    gtfs_file gtfs_f <- gtfs_file("../../includes/filtered_gtfs_cleaned");
    date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
    shape_file boundary_shp <- shape_file("../../includes/stops_points_wgs84.shp");
    

    geometry shape <- envelope(boundary_shp);
	
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        
        write "Le premier jour du GTFS = " + min_date_gtfs;
        write "Le dernier jour du GTFS = " + max_date_gtfs;
    
       

       
        create transport_shape from: gtfs_f { }
    }
}

// Species representing each transport shape
species transport_shape skills: [TransportShapeSkill] {
	
    init {
      
    }

    // Aspect to visualize the shape as a polygon
    aspect base {
       draw shape color: #green;
    }
}

species road {
	aspect default {
		draw shape color: #black;
	}
	int routeType;
	init {
        
    }

}


// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the transport shapes on the map
        display "Transport Shapes" {
            species transport_shape aspect: base;
            species road aspect: default;
        }
       

    }
}
