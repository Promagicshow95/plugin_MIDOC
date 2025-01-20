model GTFSreader

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../includes/tisseo_gtfs_v2");	
    shape_file boundary_shp <- shape_file("../includes/boundaryTLSE-WGS84PM.shp");

    // Geometry of the boundary
    geometry shape <- envelope(boundary_shp);

    // Initialization section
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        // Create transport_shape agents from the GTFS data
        create transport_shape from: gtfs_f {
            write "Shape created with ID: " + shapeId + " and " + length(points) + " points.";
        }
    }
}

// Species representing each transport shape
species transport_shape skills: [TransportShapeSkill] {

    init {
        write "Transport shape initialized: " + shapeId + " location:"+ location +  ", points: " + length(points);
    }

    // Aspect to visualize the shape as a polygon
    aspect base {
        draw polyline (points) color: #green;
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
