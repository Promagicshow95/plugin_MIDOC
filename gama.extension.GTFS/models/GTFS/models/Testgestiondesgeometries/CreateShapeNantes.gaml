model CreateShape

global  {
    gtfs_file gtfs_f <- gtfs_file("../../includes/nantes_gtfs");
    date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
    shape_file boundary_shp <- shape_file("../../includes/shapeFileNantes.shp");
    

    geometry shape <- envelope(boundary_shp);
	
    init {

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


// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the transport shapes on the map
        display "Transport Shapes" {
            species transport_shape aspect: base;
        }   

    }
}
