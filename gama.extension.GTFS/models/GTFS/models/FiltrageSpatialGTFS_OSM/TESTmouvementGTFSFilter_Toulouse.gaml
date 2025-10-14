model TESTmouvementGTFSFilter

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/ToulouseFilter_gtfs");
    shape_file boundary_shp <- shape_file("../../includes/shapeFileToulouseFilter.shp");
    geometry shape <- envelope(boundary_shp);

    date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
    date starting_date <- date("2025-06-10T08:00:00");
    float step <- 0.4 #s;
    int current_day <- 0;
    int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    int current_seconds_mod <- 0;
    
    int simulation_start_time;
    map<int, graph> shape_graphs;
    map<int, geometry> shape_polylines;
    map<int, list<float>> shape_cumulative_distances;

    init {
        simulation_start_time <- (starting_date.hour * 3600) + (starting_date.minute * 60) + starting_date.second;
        write "⏰ Simulation démarre à: " + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m";
        
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;

        loop s over: transport_shape {
            shape_graphs[s.shapeId] <- as_edge_graph(s);
            shape_polylines[s.shapeId] <- s.shape;
            
            if (s.shape != nil) {
                do calculate_cumulative_distances(s.shapeId, s.shape);
            }
        }
    }
    
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
        if (ordered_trip_ids != nil) {
            current_trip_index <- find_next_trip_index_after_time(simulation_start_time);
            write "🕐 Stop " + self + ": Premier trip à l'index " + current_trip_index + 
                  " (à partir de " + (simulation_start_time / 3600) + "h" + ((simulation_start_time mod 3600) / 60) + "m)";
        }
    }
    
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
                    speed:: 10.0 * step,
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
    
    list<point> travel_points;
    list<float> traveled_dist_list;
    int travel_shape_idx <- 0;
    point moving_target;
    bool is_stopping -> moving_target = nil;
    float close_dist <- 10.0 #m;  // ✅ AUGMENTÉ de 5m à 10m
    float min_dist_to_move <- 5.0 #m;

    init {
        geometry polyline <- shape_polylines[shapeID];
        if (polyline != nil) {
            travel_points <- polyline.points;
            traveled_dist_list <- shape_cumulative_distances[shapeID];
        }
        
        if (length(travel_points) > 0) {
            location <- travel_points[0];
        }
    }

    reflex update_time {
        current_local_time <- int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    }

    // ✅ SÉCURITÉ 1: Timeout après 2 heures
    reflex check_timeout {
        if (current_local_time - creation_time > 7200) {
            write "⚠️ Bus " + trip_id + " supprimé (timeout 2h)";
            do die;
        }
    }

    // ✅ SÉCURITÉ 2: Terminus forcé
    reflex force_terminus when: current_stop_index >= length(departureStopsInfo) {
        write "✅ Bus " + trip_id + " terminus atteint (index >= length)";
        do die;
    }

    // ✅ SÉCURITÉ 3: Hors limites géographiques
    reflex check_bounds {
    float max_distance <- 20000.0; // 20km du centre
    if (location distance_to shape.location > max_distance) {
        write "⚠️ Bus " + trip_id + " trop loin du centre → supprimé";
        do die;
    	}
	}

    reflex wait_at_stop when: waiting_at_stop {
        int stop_time <- departureStopsInfo[current_stop_index].value as int;
        if (current_local_time >= stop_time) {
            do calculate_segment_speed;
            waiting_at_stop <- false;
        }
    }
    
    action calculate_segment_speed {
        if (current_stop_index >= length(departureStopsInfo) - 1) {
            return;
        }
        
        int current_time <- departureStopsInfo[current_stop_index].value as int;
        int next_time <- departureStopsInfo[current_stop_index + 1].value as int;
        int segment_time <- next_time - current_time;
        
        if (segment_time <= 0) {
            speed <- 10.0 * step;
            return;
        }
        
        point current_stop_location <- departureStopsInfo[current_stop_index].key.location;
        point next_stop_location <- departureStopsInfo[current_stop_index + 1].key.location;
        
        int start_poly_idx <- find_closest_polyline_point(current_stop_location);
        int end_poly_idx <- find_closest_polyline_point(next_stop_location);
        
        float segment_distance <- 0.0;
        if (end_poly_idx > start_poly_idx and length(traveled_dist_list) > end_poly_idx) {
            segment_distance <- traveled_dist_list[end_poly_idx] - traveled_dist_list[start_poly_idx];
        } else {
            segment_distance <- (current_stop_location distance_to next_stop_location) * 1.3;
        }
        
        float vitesse_reelle <- segment_distance / segment_time;
        float vitesse_compensee <- vitesse_reelle * step;
        speed <- max(2.0 * step, min(vitesse_compensee, 25.0 * step));
    }
    
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

    reflex move when: not is_stopping {
        do goto target: moving_target speed: speed;
        if (location distance_to moving_target < close_dist) {
            location <- moving_target;
            moving_target <- nil;
        }
    }
    
    reflex follow_route when: is_stopping {
        int time_now <- current_local_time;
        
        // ✅ AMÉLIORATION: Vérification prioritaire du terminus
        if (current_stop_index >= length(departureStopsInfo) - 1) {
            write "✅ Bus " + trip_id + " dernier arrêt atteint";
            do die;
            return;
        }
        
        // Vérifier si on a atteint l'arrêt suivant
        if (current_stop_index < length(departureStopsInfo) - 1) {
            point next_stop_pos <- departureStopsInfo[current_stop_index + 1].key.location;
            float dist_to_next_stop <- location distance_to next_stop_pos;
            
            // ✅ AMÉLIORATION: Distance de tolérance augmentée
            if (dist_to_next_stop <= close_dist * 1.5) {
                do arrive_at_stop;
                return;
            }
        }
        
        int departure_time <- departureStopsInfo[current_stop_index].value as int;
        if (time_now < departure_time) {
            return;
        }
        
        if (length(travel_points) > 0 and travel_shape_idx < length(travel_points) - 1) {
            float target_move_dist <- min_dist_to_move * step;
            
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
    
    action arrive_at_stop {
        int expected_arrival_time <- departureStopsInfo[current_stop_index + 1].value as int;
        int actual_time <- current_local_time;
        int time_diff <- expected_arrival_time - actual_time;
        
        if (time_diff < 0) {
            arrival_time_diffs_neg << time_diff;
        } else {
            arrival_time_diffs_pos << time_diff;
        }
        
        current_stop_index <- current_stop_index + 1;
        
        // ✅ AMÉLIORATION: Vérification immédiate après incrémentation
        if (current_stop_index >= length(departureStopsInfo)) {
            write "✅ Bus " + trip_id + " tous arrêts complétés";
            do die;
            return;
        }
        
        if (current_stop_index < length(departureStopsInfo)) {
            target_location <- departureStopsInfo[current_stop_index].key.location;
            waiting_at_stop <- true;
        }
    }

    aspect base {
        rgb vehicle_color;
        if (route_type = 0) {
            vehicle_color <- #blue;
        } else if (route_type = 1) {
            vehicle_color <- #red;
        } else if (route_type = 2) {
            vehicle_color <- #green;
        } else if (route_type = 3) {
            vehicle_color <- #orange;
        } else if (route_type = 6) {
            vehicle_color <- #purple;
        } else {
            vehicle_color <- #gray;
        }
        
        draw rectangle(90, 120) color: vehicle_color rotate: heading;
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