model GTFSreader

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");    
    shape_file boundary_shp <- shape_file("../../includes/boundaryTLSE-WGS84PM.shp");
    geometry shape <- envelope(boundary_shp);
    graph road_network;
    
    // Heure de début de la simulation
    date starting_date <- date("2024-02-21T20:05:00");
    float step <- 1#mn;

    init {
        write "Loading GTFS contents from: " + gtfs_f;
        
        // Création des agents basés sur les données GTFS
        create transport_shape from: gtfs_f {}
        create bus_stop from: gtfs_f {}

        // Construction du graphe routier (basé sur les transport_shape comme routes)
        road_network <- as_edge_graph(transport_shape);

		bus_stop starts_stop <- bus_stop[1017];
		write "la listes des bus tops: " + starts_stop.departureStopsInfo;
		int current_hour <- current_date.hour;
        int current_minute <- current_date.minute;
        int current_second <- current_date.second;

        string current_hour_string <- (current_hour < 10 ? "0" + string(current_hour) : string(current_hour));
        string current_minute_string <- (current_minute < 10 ? "0" + string(current_minute) : string(current_minute));
        string current_second_string <- (current_second < 10 ? "0" + string(current_second) : string(current_second));

        string formatted_time <- current_hour_string + ":" + current_minute_string + ":" + current_second_string;
        write "formatted_time: " + formatted_time;
			string departure_time <- "20:20:00";
		// créer un bus 
		create bus {
			departureStopsInfo <- starts_stop.departureStopsInfo['trip_1900861']; 
			
			list<bus_stop> list_bus_stops <- departureStopsInfo collect (each.key);
			write "list_bus_stops: " + list_bus_stops;
			list<string> list_times <- departureStopsInfo collect (each.value);
			write "list times: " +list_times;
			
			
			
			// Comparaison des chaînes "HH:mm:ss"
			if (formatted_time > departure_time) {
    		write "L'heure actuelle (" + formatted_time + ") est **après** l'heure de départ (" + departure_time + ").";
			} else if (formatted_time < departure_time) {
    		write "L'heure actuelle (" + formatted_time + ") est **avant** l'heure de départ (" + departure_time + ").";
			} else {
    		write "L'heure actuelle (" + formatted_time + ") correspond exactement à l'heure de départ (" + departure_time + ").";
			}
			
			
			point target_location <- list_bus_stops[1].location;
			
			write "target location : " + target_location;
			location <- departureStopsInfo[0].key.location;
			write "location : " + location;
			target <- departureStopsInfo[1].key.location;
			write "target "+ target;
			
			
		}
		

        // Création d'une liste d'arrêts pour le bus
        list<bus_stop> bus_route <- bus_stop where (each.stopName in ["Balma-Gramont", "Argoulets", "Roseraie", "Jolimont"]);
        list<point> stop_locations <- bus_route collect (each.location);

        if (length(stop_locations) > 1) {
            create bus number: 1 with: [location: stop_locations[0], route_stops: stop_locations];
            write "Bus créé, départ de " + stop_locations[0];
        } else {
            write "Erreur: pas assez d'arrêts trouvés.";
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
    list<point> route_stops;  
    int current_stop_index <- 0;  
    float stop_duration <- 5.0;  
    bool is_stopped <- false;  
    int current_hour_string;
    
    list<pair<bus_stop,string>> departureStopsInfo;
    point target;
    int index_next_stop <- 2;

    init {
        speed <- 20.0;  
        do move_to_next_stop;
    }

    // Déplacement vers le prochain arrêt
    reflex move when: not is_stopped {
        if (current_stop_index < length(route_stops)) {
            point next_stop <- route_stops[current_stop_index];

            if (location distance_to next_stop > 1) {
                do goto target: next_stop on: road_network speed: speed;
            } else {
                do stop_at_station;
            }
        } else {
            write "Bus a atteint le dernier arrêt.";
        }
    }

    //Action pour aller vers le prochain arrêt
    action move_to_next_stop {
        if (current_stop_index < length(route_stops)) {
            point next_stop <- route_stops[current_stop_index];
            write "Bus se dirige vers l'arrêt: " + next_stop;
            is_stopped <- false;
        } else {
            write "Fin du trajet.";
        }
    }

    //Action pour s'arrêter à un arrêt
    action stop_at_station {
        write "Bus arrêté à l'arrêt " + current_stop_index;
        is_stopped <- true;
        current_stop_index <- current_stop_index + 1;

 //       do after (stop_duration #s) resume_movement;
    }

    // Redémarrer après l'arrêt
    action resume_movement {
        is_stopped <- false;
        do move_to_next_stop;
    }

    aspect base {
        draw rectangle(100, 50) color: #red at: location rotate: heading;
    }
}

// Expérience GUI pour visualiser la simulation
experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {
            species transport_shape aspect: base;
            species bus_stop aspect: base;
            species bus aspect: base;
        }
    }
}