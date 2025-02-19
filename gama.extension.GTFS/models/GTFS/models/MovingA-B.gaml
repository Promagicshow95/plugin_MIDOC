/**
* Name: MovingAB
* Based on the internal empty template. 
* Author: tiend
* Tags: 
*/


model MovingAB

global {
    gtfs_file gtfs_f <- gtfs_file("../includes/tisseo_gtfs_v2");    
    shape_file boundary_shp <- shape_file("../includes/boundaryTLSE-WGS84PM.shp");
    geometry shape <- envelope(boundary_shp);
    graph road_network;
    
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        create transport_shape from: gtfs_f {}
        create bus_stop from: gtfs_f {}
        
        

//        road_network <- as_driving_graph(transport_shape, bus_stop);
		  road_network <- as_edge_graph(transport_shape);

        bus_stop start_stop <- (bus_stop first_with (each.stopName = "Balma-Gramont"));
        bus_stop end_stop <- one_of(bus_stop where (each.stopName = "Jolimont"));

        if (start_stop != nil and end_stop != nil) {
            create bus number: 1 with: (location: start_stop.location, target_location: end_stop.location);
            write "Bus created at: " + start_stop.location + " going to " + end_stop.location;
        } else {
            write "Error: Could not find start or destination stop.";
        }
    }
}

species bus_stop skills: [TransportStopSkill] {
    aspect base {
        draw circle(10) at: location color: #blue;
    }
}

species transport_shape skills: [TransportShapeSkill] {
    aspect base {
        draw shape color: #green;
    }
}

species bus skills: [moving] {
    rgb color <- #red;
    point target_location;
    bool has_arrived <- false;
    
    init {
        speed <- 1.0;
        do move_to_destination;
    }

      reflex move when: self.location != target_location {
        do goto target: target_location on: road_network speed: speed;

        if (self.location = target_location and not has_arrived) {
            write " Bus arrived at destination: " + target_location;
            has_arrived <- true;
            do stop_bus;
        }
    }

    action move_to_destination {
        write "Bus moving to: " + target_location;
    }

    action stop_bus {
        speed <- 0.0;
        write "Bus has stopped at its destination.";
    }

    aspect base {
        draw rectangle(100, 50) color: #red at: location rotate: heading;
    }
}



experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {
            species transport_shape aspect: base;
            species bus_stop aspect: base;
            species bus aspect: base;
        }
    }
}


