model GTFSreader

global {
    gtfs_file gtfs_f <- gtfs_file("../includes/tisseo_gtfs_v2");    
    shape_file boundary_shp <- shape_file("../includes/boundaryTLSE-WGS84PM.shp");
    geometry shape <- envelope(boundary_shp);

    init {
        write "Loading GTFS contents from: " + gtfs_f;
        create transport_shape from: gtfs_f {}
        create bus_stop from: gtfs_f {}
        ask bus_stop { do customInit; }
    }
}

species bus_stop skills: [TransportStopSkill] {
    action customInit {
      
    }
    aspect base {
        draw circle(100.0) at: location color:#blue;
    }
}

species transport_shape skills: [TransportShapeSkill] {
    init {
       
    }
    aspect base {
        draw shape color: #green;
    }
}

experiment GTFSExperiment type: gui {
    output {
        display "Bus Stops and Transport Shapes" {
            species transport_shape aspect: base;
            species bus_stop aspect: base;
        }
    }
}
