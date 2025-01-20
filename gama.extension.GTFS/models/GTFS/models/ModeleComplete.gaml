model GTFSreader

global {
    // Path to the GTFS file
    gtfs_file gtfs_f <- gtfs_file("../includes/tisseo_gtfs_v2");	
    shape_file boundary_shp <- shape_file("../includes/boundaryTLSE-WGS84PM.shp");

    // Geometry of the boundary
    geometry shape <- envelope(boundary_shp);
    
   	// Driving skills parameters
	float lane_width_ <- 0.7; 
	graph ROAD_NETWORK;
	
	// Simulation parameters
	float step <- 0.1 #s;
	
	date starting_date <- date(string("2020-03-10 08:00:00"));
	
	// To change the location of stops
	list<point> shapePoints <- [];

    // Initialization section
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        // Create transport_shape agents from the GTFS data
        create transport_shape from: gtfs_f {
 //           write "Shape created with ID: " + shapeId + " and " + length(points) + " points.";
        }
        
                // Create bus_stop agents from the GTFS data
       create bus_trip from: gtfs_f  {}
       
         create transport_route from: gtfs_f{
            
        }

           // Create bus_stop agents from the GTFS data
	      create bus_stop from: gtfs_f  {

       }
       ask bus_stop{ do customInit;}
       write "Test";
       
       do FindBusStopInShapes;
       
       
    }
    
    action FindBusStopInShapes{
		
		write("FindBusStopInShapes...");
		
				
		// Get all points
		loop shape_agent over: transport_shape{
			
//			write shape_agent.location;

			add location to: shapePoints;
			
		}
		
		// Set location of busStops on shapes
		ask bus_stop{
			
			loop stop_agent over: bus_stop{

			}
			
			location <- closest_to (shapePoints, self.location);
		
			
			
			
			
		}
	
	}

}

species transport_route skills: [TransportRouteSkill] {
    init {
//        write "Route initialized: " + routeId + ", Short Name: " + shortName + ", Type: " + type;
    }
}
// Species representing each transport shape
species transport_shape skills: [TransportShapeSkill] {

    init {
//        write "Transport shape initialized: " + shapeId + ", points: " + length(points);
    }

    // Aspect to visualize the shape as a polygon
    aspect base {
        draw polyline (points) color: #green;
    }
}

species bus_stop skills: [TransportStopSkill] {
	
    init {
//        write "Transport shape initialized: " + shapeId + ", points: " + length(points);
    }
    action customInit {
    }
     aspect base {
		draw circle (100.0) at: location color:#blue;
     }
}




species bus_trip skills: [TransportTripSkill] {
	init {
//        write "Bus trip initialized: " + tripId + ", " + stopsInOrder;
    }

    
     aspect base {
		draw circle (100.0)  color:#blue;	
     }
     
}






// GUI-based experiment for visualization
experiment GTFSExperiment type: gui {
    
    // Output section to define the display
    output {
        // Display the transport shapes on the map
        display "Transport Shapes" {
            species transport_shape aspect: base  ;
            species bus_stop aspect: base  ;
        }
    }
}
