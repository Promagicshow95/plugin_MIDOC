model GTFSreader

global  {
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
    shape_file boundary_shp <- shape_file("../../includes/shapeFileToulouse.shp");
    

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
