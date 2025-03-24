model MovingAB

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");    
    shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
    geometry shape <- envelope(boundary_shp);
    graph road_network;
    
      //tolerance for reconnecting nodes
	float tolerance <- 1.0;
	
	//if true, split the lines at their intersection
	bool split_lines <- true;
	
	//if true, keep only the main connected components of the network
	bool reduce_to_main_connected_components <- true;

    init {
        write "Loading GTFS contents from: " + gtfs_f;

        create bus_stop from: gtfs_f {}
        
        create transport_shape from: gtfs_f {}
        
        list<geometry> clean_lines <- clean_network(transport_shape collect each.shape, tolerance, split_lines, reduce_to_main_connected_components) ;

        create road from: clean_lines{
        	if(self.shape intersects world.shape){}
        	else {
        		do die;
        	}
      
        }
        
        road_network <- as_edge_graph(road);

        bus_stop start_stop <- bus_stop first_with (each.stopName = "Sept Deniers - Salvador Dali");
        bus_stop end_stop <- one_of(bus_stop where (each.stopName = "Fonsegrives Entiore"));
        
        bus_stop choisir_stop <- bus_stop[32];
        string first_time <- choisir_stop.departureStopsInfo.values()[0][0];
        write "premier l'heure départ: "+first_time;

        if (start_stop != nil and end_stop != nil) {
            create bus number: 1 with: (location: start_stop.location, target_location: end_stop.location);
            //write "Bus created at: " + start_stop.location + " going to " + end_stop.location;
        } else {
            //write "Error: Could not find start or destination stop.";
        }
    }
}

species bus_stop skills: [TransportStopSkill] {
    aspect base {
        draw circle(10) color: #blue;
    }
}

species transport_shape skills: [TransportShapeSkill] {


}

species road {
    aspect default {
        if (routeType = 3)  { draw shape color: #yellow; }
        if (routeType != 3)  { draw shape color: #black; }
    }
    int routeType; 
    int shapeId;
}

species bus skills: [moving] {
    point target_location;

    init {
        speed <- 1.0;
    }

    reflex move when: target_location != nil {
        do goto target: target_location on: road_network speed: speed;

        if (self.location = target_location) {
            write "Bus arrived at destination: " + target_location;
            target_location <- nil;
        }
    }

    aspect base {
        draw rectangle(100, 50) color: #red rotate: heading;
    }
}

experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {
            species bus_stop aspect: base;
            species bus aspect: base;
            species road aspect: default;
        }
    }
}
