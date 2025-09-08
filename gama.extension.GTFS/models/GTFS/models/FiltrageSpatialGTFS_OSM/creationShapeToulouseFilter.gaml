model GTFSreader

global  {
    gtfs_file gtfs_f <- gtfs_file("../../includes/ToulouseFilter_gtfs");
    shape_file boundary_shp <- shape_file("../../includes/shapeFileToulouseFilter.shp");
    

    geometry shape <- envelope(boundary_shp);
	
    init {
		create bus_stop from: gtfs_f  {}
		
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

species bus_stop skills: [TransportStopSkill] {

    
     aspect base {    	
		draw circle (100.0) at: location color:#blue;	
     }
}



// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the transport shapes on the map
        display "Transport Shapes" {
            species transport_shape aspect: base;
            species bus_stop aspect: base;
        }
       

    }
}
