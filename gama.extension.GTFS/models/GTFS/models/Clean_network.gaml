/**
* Name: Cleannetwork
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model Cleannetwork

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../includes/tisseo_gtfs_v2");	
    shape_file boundary_shp <- shape_file("../includes/boundaryTLSE-WGS84PM.shp");

    // Geometry of the boundary
    geometry shape <- envelope(boundary_shp);
    
	//clean or not the data
	bool clean_data <- true;
	
	//tolerance for reconnecting nodes
	float tolerance <- 3.0;
	
	//if true, split the lines at their intersection
	bool split_lines <- true;
	
	//if true, keep only the main connected components of the network
	bool reduce_to_main_connected_components <- true;
	
	string legend <- not clean_data ? "Raw data" : ("Clean data : tolerance: " + tolerance + "; split_lines: " + split_lines + " ; reduce_to_main_connected_components:" + reduce_to_main_connected_components );
	
    // Initialization section
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        // Create transport_shape agents from the GTFS data
        create transport_shape from: gtfs_f {
            write "Shape created with ID: " + shapeId ;
        }
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
// Species for analysis or additional actions
species shape_analyzer skills: [] {
    reflex check_shapes {
        write "Number of transport shapes created: " + length(transport_shape);
    }

    aspect base {
        draw circle (50.0) at: location color:#red;
    }
}

// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the transport shapes on the map
        display "Transport Shapes" {
            species transport_shape aspect: base;
            species shape_analyzer aspect: base;
        }
    }
}
