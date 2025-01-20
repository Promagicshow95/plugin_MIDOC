model TransportRouteSkill

global {
    // Path to the GTFS file
    gtfs_file tisseo_gtfs <- gtfs_file("../includes/tisseo_gtfs_v2");
    shape_file boundary_shp <- shape_file("../includes/boundaryTLSE-WGS84PM.shp");
    
    geometry shape <- envelope(boundary_shp);
    
    // Initialization section
    init {
        write "Loading GTFS contents from: " + tisseo_gtfs;
        
        // Create route agents from the GTFS data
        create transport_route from: tisseo_gtfs {
            write "Route created: " + routeId + ", " + shortName + ", type: " + type;
        }
    }
}

species transport_route skills: [TransportRouteSkill] {
    init {
        write "Route initialized: " + routeId + ", Short Name: " + shortName + ", Type: " + type;
    }
}
species route_checker skills: [TransportRouteSkill] {
    reflex check_routes {
        write "Number of routes created: " + length(transport_route);  // Displays the number of created routes
    }

}

// GUI-based experiment for visualization
experiment RouteVisualization type: gui {
    output {
        // Display the transport routes on the map
        display "Transport Routes" {
            // Display the transport_route agents
          

        }
    }
}
