model GTFS_Simulation


global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
    shape_file cleaned_road_shp <- shape_file("../../includes/cleaned_network.shp");
    geometry shape <- envelope(cleaned_road_shp);
    graph road_network;
    

    // Heure de début de la simulation
    date starting_date <- date("2024-02-21T20:00:00");
    
    float step <- 1#mn;
    
    string formatted_starting_date_time;
    
    
    init {
        write "Loading GTFS contents from: " + gtfs_f;
        create road from: cleaned_road_shp;
        road_network <- as_edge_graph(road); 
        create bus_stop from: gtfs_f {
            int current_hour <- current_date.hour;
            int current_minute <- current_date.minute;
            int current_second <- current_date.second;
        
            string current_hour_string <- (current_hour < 10 ? "0" + string(current_hour) : string(current_hour));
            string current_minute_string <- (current_minute < 10 ? "0" + string(current_minute) : string(current_minute));
            string current_second_string <- (current_second < 10 ? "0" + string(current_second) : string(current_second));
            
            formatted_starting_date_time <- current_hour_string + ":" + current_minute_string + ":" + current_second_string;
            write "formatted_time: " + formatted_starting_date_time; 

            if (length(departureStopsInfo) > 0) {
                list<pair<bus_stop, string>> trip_info <- departureStopsInfo['trip_1900861'];
                list<bus_stop> list_bus_stops <- trip_info collect (each.key);
                list<string> list_times <- trip_info collect (each.value);
                write "list of bus stop: " + list_bus_stops;
                write "list of time: "+ list_times;

                if (length(list_bus_stops) > 0 and formatted_starting_date_time >= list_times[0]) {
                    write "Création d'un bus au départ de " + stopName;
                    create bus with: [
                        departureStopsInfo::trip_info,
                        list_bus_stops::list_bus_stops,
                        list_times::list_times,
                        current_stop_index::0,
                        location::list_bus_stops[0].location,
                        target_location::list_bus_stops[1].location,
                        formatted_starting_date_time::formatted_starting_date_time // ✅ Ajouté pour que le bus puisse l'utiliser
                    ];
                }
            }
        }
    }
}

// Espèce bus_stop avec la gestion des départs
species bus_stop skills: [TransportStopSkill] {
    aspect base {
        draw circle(10) color: #blue;
    }
}

// Espèce road pour afficher les routes
species road {
    aspect default {
        draw shape color: #black;
    }
}

// Espèce bus qui attend son heure de départ à chaque arrêt
species bus skills: [moving] {
    aspect base {
        draw rectangle(100, 50) color: #red at: location rotate: heading;
    }

    list<bus_stop> list_bus_stops;
    list<string> list_times;
    int current_stop_index;
    point target_location;
    list<pair<bus_stop, string>> departureStopsInfo;
    bool is_waiting <- true;
    string formatted_starting_date_time; // ✅ Maintenant bien passé au bus

    init {
        speed <- 0.5;
    }

    // Vérifier l'heure de départ avant de repartir
    reflex check_departure_time when: is_waiting {
        string departure_time <- list_times[current_stop_index];

        if (formatted_starting_date_time >= departure_time) {
            is_waiting <- false;
            write "Départ du bus vers " + list_bus_stops[current_stop_index].stopName;
        }
    }

    // Déplacement vers le prochain arrêt
    reflex move when: target_location != nil and not is_waiting {
        do goto target: target_location on: road_network speed: speed;
    }

    // Vérifier l'arrivée et gérer l'attente
    reflex check_arrival when: self.location = target_location {
        write "Bus arrivé à " + list_bus_stops[current_stop_index].stopName;

        if (current_stop_index < length(list_bus_stops) - 1) {
            current_stop_index <- current_stop_index + 1;
            target_location <- list_bus_stops[current_stop_index].location;
            is_waiting <- true;
            write "Bus attend à " + list_bus_stops[current_stop_index - 1].stopName + " jusqu'à " + list_times[current_stop_index];
        } else {
            write "Bus a atteint le dernier arrêt.";
            target_location <- nil;
        }
    }
}

// Expérience GUI pour visualiser la simulation
experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {
            species bus_stop aspect: base;
            species bus aspect: base;
            species road aspect: default;
        }
    }
}
