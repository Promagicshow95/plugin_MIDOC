model GTFSMultiBusAntiJump

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileToulouse.shp");
    geometry shape <- envelope(boundary_shp);

    // --- Paramètres temporels ---
    date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
    date starting_date <- date("2025-05-17T00:00:00");
    float step <- 20 #s;
    int current_day <- 0;
    string formatted_time;
    int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    int current_seconds_mod <- 0;

    // --- GTFS & navigation ---
    map<int, graph> shape_graphs;
    map<int, geometry> shape_polylines; // polyline originale pour chaque shape_id

    // --- Système anti-saut : paramètres globaux ---
    bool enable_anti_jump <- true;
    float jump_detection_threshold <- 150.0 #m;
    float waypoint_spacing <- 25.0 #m;
    bool preventive_waypoints <- true;

    int total_trips_to_launch <- 0;
    int launched_trips_count <- 0;
    list<string> launched_trip_ids <- [];

    init {
        write "GTFS de " + min_date_gtfs + " à " + max_date_gtfs;
        current_day <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;

        // Prégénérer graphes et polylines par shape_id
        loop s over: transport_shape {
            shape_graphs[s.shapeId] <- as_edge_graph(s);
            shape_polylines[s.shapeId] <- s.shape;
        }
    }

    int get_time_now {
        int dof <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        if dof > current_day {
            return time_24h + 86400;
        }
        return time_24h;
    }

    reflex update_time_every_cycle {
        current_seconds_mod <- get_time_now();
    }

    reflex show_trip_count when: cycle = 1 {
        // MODIFICATION : Filtrer seulement les métros (route_type = 1)
        total_trips_to_launch <- sum(bus_stop where (each.routeType = 1) collect each.tripNumber);
        write "🚇 Total trips METRO to launch = " + total_trips_to_launch;
    }

    reflex check_new_day when: launched_trips_count >= total_trips_to_launch {
        int sim_day_index <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        if sim_day_index > current_day {
            current_day <- sim_day_index;
            launched_trips_count <- 0;
            launched_trip_ids <- [];
            ask bus_stop {
                current_trip_index <- 0;
            }
            write "🌙 Passage au jour " + current_day;
        }
    }
}

species bus_stop skills: [TransportStopSkill] {
    map<string, bool> trips_launched;
    list<string> ordered_trip_ids;
    int current_trip_index <- 0;

    aspect base { 
        draw circle(20) color: #blue; 
    }

    reflex init_order when: cycle = 1 {
        ordered_trip_ids <- keys(departureStopsInfo);
    }

    // MODIFICATION : Lancer seulement les métros (route_type = 1)
    reflex launch_vehicles when: (departureStopsInfo != nil and current_trip_index < length(ordered_trip_ids) and self.routeType = 1) {
        string trip_id <- ordered_trip_ids[current_trip_index];
        list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
        string departure_time <- trip_info[0].value;

        if (current_seconds_mod >= int(departure_time) and not (trip_id in launched_trip_ids)) {
            int shape_found <- tripShapeMap[trip_id] as int;
            if (shape_found != 0) {
                int shape_id <- shape_found;
                geometry polyline <- shape_polylines[shape_id];

                create bus with: [
                    departureStopsInfo:: trip_info,
                    current_stop_index:: 0,
                    location:: trip_info[0].key.location,
                    target_location:: trip_info[1].key.location,
                    trip_id:: trip_id,
                    shapeID:: shape_id,
                    route_type:: self.routeType,
                    original_shape_polyline:: polyline,
                    local_network:: shape_graphs[shape_id],
                    enable_anti_jump:: enable_anti_jump,
                    jump_detection_threshold:: jump_detection_threshold,
                    waypoint_spacing:: waypoint_spacing,
                    preventive_waypoints:: preventive_waypoints,
                    creation_time:: current_seconds_mod,
                    loop_starting_day:: current_day
                ];

                launched_trips_count <- launched_trips_count + 1;
                launched_trip_ids <- launched_trip_ids + trip_id;
                current_trip_index <- (current_trip_index + 1) mod length(ordered_trip_ids);
            }
        }
    }
}

species bus skills: [moving] {
    graph local_network;
    geometry original_shape_polyline;
    bool enable_anti_jump <- true;
    float jump_detection_threshold <- 150.0 #m;
    float waypoint_spacing <- 25.0 #m;
    bool preventive_waypoints <- true;

    list<pair<bus_stop,string>> departureStopsInfo;
    int current_stop_index <- 0;
    point target_location;
    string trip_id;
    int shapeID;
    int route_type;
    int loop_starting_day;
    int creation_time;
    int end_time;
    int real_duration;
    int current_local_time;

    // --- Système anti-saut individuel ---
    list<point> current_waypoints <- [];
    int waypoint_index <- 0;
    bool using_waypoints <- false;
    int anti_jump_activations <- 0;

    // Statistiques
    float total_distance_traveled <- 0.0;
    int network_moves <- 0;
    int waypoint_moves <- 0;
    int direct_moves <- 0;
    list<int> arrival_time_diffs_pos <- [];
    list<int> arrival_time_diffs_neg <- [];
    bool waiting_at_stop <- true;

    init {
        speed <- 60 #km/#h;
        creation_time <- get_local_time_now();
    }

    int get_local_time_now {
        int dof <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        if dof > loop_starting_day {
            return time_24h + 86400;
        }
        return time_24h;
    }

    reflex update_time_every_cycle {
        current_local_time <- get_local_time_now();
    }

    reflex wait_at_stop when: waiting_at_stop {
        int stop_time <- departureStopsInfo[current_stop_index].value as int;
        if (current_local_time >= stop_time) { 
            waiting_at_stop <- false; 
        }
    }

    // --- REFLEX DEPLACEMENT HYBRIDE (anti-saut inclus) ---
    reflex move when: not waiting_at_stop and self.location distance_to target_location > 5#m {
        float distance_to_target <- location distance_to target_location;
        bool movement_successful <- false;
        point previous_location <- location;

        // Activation préventive sur segment long
        if (!using_waypoints and preventive_waypoints and distance_to_target > jump_detection_threshold) {
            do activate_anti_jump_system;
            anti_jump_activations <- anti_jump_activations + 1;
        }

        // 1. Navigation par waypoints si actif
        if (using_waypoints and length(current_waypoints) > waypoint_index) {
            point current_waypoint <- current_waypoints[waypoint_index];
            float dist_wp <- location distance_to current_waypoint;
            if (dist_wp <= 10#m) {
                waypoint_index <- waypoint_index + 1;
                if (waypoint_index >= length(current_waypoints)) {
                    using_waypoints <- false;
                }
            } else {
                do goto target: current_waypoint speed: speed;
                waypoint_moves <- waypoint_moves + 1;
                movement_successful <- true;
            }
        }

        // 2. Navigation graphe
        if (!using_waypoints and local_network != nil) {
            path network_path <- path_between(local_network, location, target_location);
            if (network_path != nil and length(network_path.edges) > 0) {
                do goto target: target_location on: local_network speed: speed;
                network_moves <- network_moves + 1;
                movement_successful <- true;
            }
        }

        // 3. Navigation directe + détection saut
        if (!using_waypoints and !movement_successful) {
            do goto target: target_location speed: speed;
            float move_dist <- previous_location distance_to location;
            // Détection saut simple : déplacement trop long
            if (enable_anti_jump and move_dist > jump_detection_threshold * 0.7) {
                write "🚨 Saut détecté sur bus " + trip_id + ", activation anti-saut";
                location <- previous_location;
                do activate_anti_jump_system;
                anti_jump_activations <- anti_jump_activations + 1;
            } else {
                direct_moves <- direct_moves + 1;
                movement_successful <- true;
            }
        }

        // Maj distance totale
        if (movement_successful) {
            total_distance_traveled <- total_distance_traveled + (previous_location distance_to location);
        }
        // Correction position finale si très proche
        if (location distance_to target_location < 5#m) { 
            location <- target_location; 
        }
    }

    // --- Activation système anti-saut ---
    action activate_anti_jump_system {
        using_waypoints <- true;
        waypoint_index <- 0;
        current_waypoints <- [];
        do generate_polyline_waypoints;
        write "   [Bus " + trip_id + "] Waypoints générés : " + string(length(current_waypoints));
    }

    action generate_polyline_waypoints {
        if (original_shape_polyline = nil) { 
            return; 
        }
        list<point> polyline_points <- original_shape_polyline.points;
        point current_pos <- location;
        point target_pos <- target_location;
        // Trouver index polyline le + proche pour début et fin
        int start_idx <- 0; 
        float min_dist <- 1e9;
        int end_idx <- 0; 
        float min_dist_end <- 1e9;
        loop i from: 0 to: length(polyline_points) - 1 {
            float dist <- current_pos distance_to polyline_points[i];
            if (dist < min_dist) { 
                min_dist <- dist; 
                start_idx <- i; 
            }
            float dist_end <- target_pos distance_to polyline_points[i];
            if (dist_end < min_dist_end) { 
                min_dist_end <- dist_end; 
                end_idx <- i; 
            }
        }
        int step <- max(1, int(waypoint_spacing / 15));
        loop i from: start_idx to: end_idx step: step {
            current_waypoints <- current_waypoints + [polyline_points[i]];
        }
        if (length(current_waypoints) = 0 or current_waypoints[length(current_waypoints) - 1] distance_to target_pos > 15) {
            current_waypoints <- current_waypoints + [target_pos];
        }
    }

    // --- Arrivée à un arrêt ---
    reflex check_arrival when: self.location distance_to target_location < 5#m and not waiting_at_stop {
        if (current_stop_index < length(departureStopsInfo) - 1) {
            int expected_arrival_time <- departureStopsInfo[current_stop_index].value as int;
            int actual_time <- current_local_time;
            int time_diff <- expected_arrival_time - actual_time;
            if (time_diff < 0) { 
                arrival_time_diffs_neg << time_diff; 
            } else { 
                arrival_time_diffs_pos << time_diff; 
            }
            // Étape suivante
            current_stop_index <- current_stop_index + 1;
            target_location <- departureStopsInfo[current_stop_index].key.location;
            waiting_at_stop <- true;
        }
        if (current_stop_index = length(departureStopsInfo) - 1) {
            end_time <- current_local_time;
            real_duration <- end_time - creation_time;
            do die;
        }
    }

    aspect base {
        // MODIFICATION : Couleur spécifique pour les métros
        rgb bus_color <- (route_type = 1) ? #red : ((route_type = 3) ? #green : #blue);
        draw rectangle(120, 180) color: bus_color rotate: heading;
        // MODIFICATION : Affichage spécifique pour les métros
        if (using_waypoints) {
            loop i from: waypoint_index to: length(current_waypoints) - 1 {
                draw circle(6) color: #yellow at: current_waypoints[i];
            }
        }
    }
}

species transport_shape skills: [TransportShapeSkill] {
    aspect default { 
        draw shape color: #black width: 2; 
    }
}

experiment GTFSFullNetwork type: gui {
    parameter "Système anti-saut" var: enable_anti_jump;
    parameter "Seuil saut (m)" var: jump_detection_threshold min: 50.0 max: 300.0;
    parameter "Espacement waypoints (m)" var: waypoint_spacing min: 10.0 max: 50.0;
    parameter "Waypoints préventifs" var: preventive_waypoints;
    output {
        display "Bus Simulation" {
            species bus_stop aspect: base refresh: true;
            species bus aspect: base;
            species transport_shape aspect: default;
        }
        display monitor {
    chart "Retard & avance aux arrêts" type: series {
        data "Moyenne avance" value: mean(bus collect mean(each.arrival_time_diffs_pos)) color: #green marker_shape: marker_empty style: spline;
        data "Moyenne retard" value: mean(bus collect mean(each.arrival_time_diffs_neg)) color: #red marker_shape: marker_empty style: spline;
    }
    
}

    }
}