model TESTmouvementGTFSFilter

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/NantesFilter_gtfs");
    shape_file boundary_shp <- shape_file("../../includes/shapeFileNantesFilter.shp");
    geometry shape <- envelope(boundary_shp);

    date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
    date starting_date <- date("2025-05-17T08:00:00");
    float step <- 0.4 #s;
    int current_day <- 0;
    int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    int current_seconds_mod <- 0;
    
    // === NOUVEAU: Logique de saut à l'heure choisie ===
    int simulation_start_time;

    map<int, graph> shape_graphs;
    map<int, geometry> shape_polylines;
    // === NOUVEAU: Distances cumulées pré-calculées par shape ===
    map<int, list<float>> shape_cumulative_distances;

    init {
        // === CALCUL HEURE DE DÉMARRAGE ===
        simulation_start_time <- (starting_date.hour * 3600) + (starting_date.minute * 60) + starting_date.second;
        write "⏰ Simulation démarre à: " + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m";
        
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;

        loop s over: transport_shape {
            shape_graphs[s.shapeId] <- as_edge_graph(s);
            shape_polylines[s.shapeId] <- s.shape;
            
            // === PRÉ-CALCUL DES DISTANCES CUMULÉES ===
            if (s.shape != nil) {
                do calculate_cumulative_distances(s.shapeId, s.shape);
            }
        }
    }
    
    // === ACTION: Calcul des distances cumulées le long de la polyline ===
    action calculate_cumulative_distances(int shape_id, geometry polyline) {
        list<point> points <- polyline.points;
        list<float> cumul_distances <- [0.0];
        float total_length <- 0.0;
        
        loop i from: 1 to: length(points) - 1 {
            float segment_dist <- points[i-1] distance_to points[i];
            total_length <- total_length + segment_dist;
            cumul_distances <- cumul_distances + [total_length];
        }
        
        shape_cumulative_distances[shape_id] <- cumul_distances;
    }

    reflex update_time_every_cycle {
        current_seconds_mod <- time_24h;
    }
}

species bus_stop skills: [TransportStopSkill] {
    list<string> ordered_trip_ids;
    int current_trip_index <- 0;

    aspect base {
        draw circle(50) color: #blue;
    }

    reflex init_order when: cycle = 1 {
        ordered_trip_ids <- keys(departureStopsInfo);
        // === SAUT À L'HEURE CHOISIE ===
        if (ordered_trip_ids != nil) {
            current_trip_index <- find_next_trip_index_after_time(simulation_start_time);
            write "🕐 Stop " + self + ": Premier trip à l'index " + current_trip_index + 
                  " (à partir de " + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m)";
        }
    }
    
    // === FONCTION POUR TROUVER TRIP APRÈS HEURE CIBLE ===
    int find_next_trip_index_after_time(int target_time) {
        if (ordered_trip_ids = nil or length(ordered_trip_ids) = 0) { 
            return 0; 
        }
        
        if (departureStopsInfo = nil) {
            return 0;
        }
        
        loop i from: 0 to: length(ordered_trip_ids) - 1 {
            string trip_id <- ordered_trip_ids[i];
            
            if (departureStopsInfo contains_key trip_id) {
                list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
                
                if (trip_info != nil and length(trip_info) > 0) {
                    int departure_time <- int(trip_info[0].value);
                    
                    if (departure_time >= target_time) {
                        return i;
                    }
                }
            }
        }
        return length(ordered_trip_ids);
    }

    reflex launch_bus when: (departureStopsInfo != nil and current_trip_index < length(ordered_trip_ids)) {
        string trip_id <- ordered_trip_ids[current_trip_index];
        list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
        string departure_time <- trip_info[0].value;

        if (current_seconds_mod >= int(departure_time)) {
            int shape_found <- tripShapeMap[trip_id] as int;
            if (shape_found != 0) {
                create bus with: [
                    departureStopsInfo:: trip_info,
                    current_stop_index:: 0,
                    location:: trip_info[0].key.location,
                    target_location:: trip_info[1].key.location,
                    trip_id:: trip_id,
                    shapeID:: shape_found,
                    route_type:: self.routeType,
                    local_network:: shape_graphs[shape_found],
                    speed:: 10.0 * step, // Vitesse initiale COMPENSÉE par step
                    creation_time:: current_seconds_mod
                ];

                current_trip_index <- current_trip_index + 1;
            }
        }
    }
}

species bus skills: [moving] {
    graph local_network;
    list<pair<bus_stop, string>> departureStopsInfo;
    int current_stop_index;
    point target_location;
    string trip_id;
    int shapeID;
    int route_type;
    float speed;
    int creation_time;
    int current_local_time;
    list<int> arrival_time_diffs_pos <- [];
    list<int> arrival_time_diffs_neg <- [];
    bool waiting_at_stop <- true;
    
    // === NOUVELLES VARIABLES POUR NAVIGATION PRÉCISE ===
    list<point> travel_points;          // Points de la polyline
    list<float> traveled_dist_list;     // Distances cumulées
    int travel_shape_idx <- 0;          // Index actuel sur la polyline
    point moving_target;                // Cible de mouvement courante
    bool is_stopping -> moving_target = nil;
    float close_dist <- 5.0 #m;         // Distance pour considérer arrivé
    float min_dist_to_move <- 5.0 #m;   // Distance minimum pour chaque mouvement

    init {
        // === INITIALISATION NAVIGATION PRÉCISE ===
        geometry polyline <- shape_polylines[shapeID];
        if (polyline != nil) {
            travel_points <- polyline.points;
            traveled_dist_list <- shape_cumulative_distances[shapeID];
        }
        
        // Démarrer au premier point de la polyline
        if (length(travel_points) > 0) {
            location <- travel_points[0];
        }
    }

    reflex update_time {
        current_local_time <- int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    }

    reflex wait_at_stop when: waiting_at_stop {
        int stop_time <- departureStopsInfo[current_stop_index].value as int;
        if (current_local_time >= stop_time) {
            // === CALCUL VITESSE PAR SEGMENT ===
            do calculate_segment_speed;
            waiting_at_stop <- false;
        }
    }
    
    // === ACTION: Calcul de vitesse pour le segment actuel AVEC COMPENSATION STEP ===
    action calculate_segment_speed {
        if (current_stop_index >= length(departureStopsInfo) - 1) {
            return;
        }
        
        // Temps disponible pour ce segment
        int current_time <- departureStopsInfo[current_stop_index].value as int;
        int next_time <- departureStopsInfo[current_stop_index + 1].value as int;
        int segment_time <- next_time - current_time;
        
        if (segment_time <= 0) {
            speed <- 10.0 * step; // Vitesse par défaut COMPENSÉE
            return;
        }
        
        // === DISTANCE RÉELLE LE LONG DE LA POLYLINE ===
        point current_stop_location <- departureStopsInfo[current_stop_index].key.location;
        point next_stop_location <- departureStopsInfo[current_stop_index + 1].key.location;
        
        // Trouver les indices sur la polyline les plus proches des arrêts
        int start_poly_idx <- find_closest_polyline_point(current_stop_location);
        int end_poly_idx <- find_closest_polyline_point(next_stop_location);
        
        // Distance réelle le long de la polyline
        float segment_distance <- 0.0;
        if (end_poly_idx > start_poly_idx and length(traveled_dist_list) > end_poly_idx) {
            segment_distance <- traveled_dist_list[end_poly_idx] - traveled_dist_list[start_poly_idx];
        } else {
            // Fallback: distance euclidienne * facteur
            segment_distance <- (current_stop_location distance_to next_stop_location) * 1.3;
        }
        
        // Calcul vitesse requise pour ce segment (vitesse réelle)
        float vitesse_reelle <- segment_distance / segment_time;
        
        // === COMPENSATION STEP: Multiplier par step ===
        float vitesse_compensee <- vitesse_reelle * step;
        
        // Borner la vitesse compensée dans des limites réalistes
        speed <- max(2.0 * step, min(vitesse_compensee, 25.0 * step));
        
        write "Segment " + string(current_stop_index) + ": " + string(round(segment_distance)) + 
              "m en " + segment_time + "s → vitesse réelle: " + string(round(vitesse_reelle * 3.6)) + 
              " km/h → vitesse compensée: " + string(round(speed)) + " m/tick";
    }
    
    // === ACTION: Trouver le point de polyline le plus proche d'une position ===
    int find_closest_polyline_point(point target_pos) {
        if (length(travel_points) = 0) {
            return 0;
        }
        
        int closest_idx <- 0;
        float min_dist <- target_pos distance_to travel_points[0];
        
        loop i from: 1 to: length(travel_points) - 1 {
            float dist <- target_pos distance_to travel_points[i];
            if (dist < min_dist) {
                min_dist <- dist;
                closest_idx <- i;
            }
        }
        
        return closest_idx;
    }

    // === NAVIGATION PRÉCISE LE LONG DE LA POLYLINE ===
    reflex move when: not is_stopping {
        do goto target: moving_target speed: speed;
        if (location distance_to moving_target < close_dist) {
            location <- moving_target;
            moving_target <- nil;
        }
    }
    
    reflex follow_route when: is_stopping {
        int time_now <- current_local_time;
        
        // Vérifier si on a atteint l'arrêt suivant
        if (current_stop_index < length(departureStopsInfo) - 1) {
            point next_stop_pos <- departureStopsInfo[current_stop_index + 1].key.location;
            float dist_to_next_stop <- location distance_to next_stop_pos;
            
            if (dist_to_next_stop <= close_dist) {
                // === ARRIVÉE À L'ARRÊT ===
                do arrive_at_stop;
                return;
            }
        } else {
            // Terminus atteint
            do die;
            return;
        }
        
        // Vérifier l'heure de départ
        int departure_time <- departureStopsInfo[current_stop_index].value as int;
        if (time_now < departure_time) {
            return; // Attendre l'heure de départ
        }
        
        // === NAVIGATION HOP-BY-HOP LE LONG DE LA POLYLINE ===
        if (length(travel_points) > 0 and travel_shape_idx < length(travel_points) - 1) {
            // Calculer la distance à parcourir pour ce cycle
            float target_move_dist <- min_dist_to_move * step;
            
            // Trouver le prochain point cible
            int finding_from <- travel_shape_idx;
            loop i from: travel_shape_idx + 1 to: length(travel_points) - 1 {
                travel_shape_idx <- i;
                if (length(traveled_dist_list) > i and length(traveled_dist_list) > finding_from) {
                    float moved_dist <- traveled_dist_list[i] - traveled_dist_list[finding_from];
                    if (moved_dist >= target_move_dist) {
                        break;
                    }
                }
            }
            
            point next_target <- travel_points[travel_shape_idx];
            if (moving_target != next_target) {
                moving_target <- next_target;
            }
        }
    }
    
    // === ACTION: Arrivée à un arrêt ===
    action arrive_at_stop {
        // Calcul écart temps
        int expected_arrival_time <- departureStopsInfo[current_stop_index + 1].value as int;
        int actual_time <- current_local_time;
        int time_diff <- expected_arrival_time - actual_time;
        
        if (time_diff < 0) {
            arrival_time_diffs_neg << time_diff;
        } else {
            arrival_time_diffs_pos << time_diff;
        }
        
        // Passer à l'arrêt suivant
        current_stop_index <- current_stop_index + 1;
        if (current_stop_index < length(departureStopsInfo)) {
            target_location <- departureStopsInfo[current_stop_index].key.location;
            waiting_at_stop <- true;
        }
    }

    aspect base {
        // Couleurs différentes selon le type de route
        rgb vehicle_color;
        if (route_type = 0) {
            vehicle_color <- #blue;        // Tram
        } else if (route_type = 1) {
            vehicle_color <- #red;         // Métro
        } else if (route_type = 2) {
            vehicle_color <- #green;       // Train
        } else if (route_type = 3) {
            vehicle_color <- #orange;      // Bus
        } else if (route_type = 6) {
            vehicle_color <- #purple;      // Téléo
        } else {
            vehicle_color <- #gray;        // Autres
        }
        
        draw rectangle(120, 180) color: vehicle_color rotate: heading;
    }
}

species transport_shape skills: [TransportShapeSkill] {
    aspect default {
        draw shape color: #black;
    }
}

experiment TESTmouvementGTFSFilter type: gui {
    output {
        display "Simulation Vitesse par Segment" {
            species bus_stop aspect: base;
            species bus aspect: base;
            species transport_shape aspect: default;
        }
        
        monitor "Bus actifs" value: length(bus);
        monitor "Retard moyen (s)" value: length(bus) > 0 ? round(mean(bus collect mean(each.arrival_time_diffs_neg))) : 0;
        monitor "Avance moyenne (s)" value: length(bus) > 0 ? round(mean(bus collect mean(each.arrival_time_diffs_pos))) : 0;
    }
}