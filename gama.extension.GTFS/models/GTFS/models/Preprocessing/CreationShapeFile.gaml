model GTFSreader

global skills: [gtfs_export] {
    gtfs_file gtfs_f <- gtfs_file("../../includes/filtered_gtfs");
    //shape_file boundary_shp <- shape_file("../../includes/routes.shp");

    //geometry shape <- envelope(boundary_shp);

    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        // *** Export du shapefile directement ***
        do export_shapes_to_shapefile;

        // Si tu veux ensuite créer les agents pour affichage, tu peux :
        //create transport_shape from: gtfs_f { }
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
