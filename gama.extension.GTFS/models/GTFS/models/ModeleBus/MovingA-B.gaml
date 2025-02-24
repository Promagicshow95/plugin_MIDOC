model MovingAB

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");    
    shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
    shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp"); 
    geometry shape <- envelope(boundary_shp);
    graph road_network;

    init {
        write "Loading GTFS contents from: " + gtfs_f;

        create bus_stop from: gtfs_f {}

        create road from: cleaned_road_shp;
        
        road_network <- as_edge_graph(road);

        bus_stop start_stop <- bus_stop first_with (each.stopName = "Balma-Gramont");
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
        draw circle(10) color: #blue;
    }
}

species road {
    aspect default {
        draw shape color: #black;
    }
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
