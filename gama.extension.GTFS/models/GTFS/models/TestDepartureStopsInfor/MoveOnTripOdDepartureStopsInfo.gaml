model MoveOnTripOfDepartureStopsInfor

global {
	// Path to the GTFS file
	string gtfs_f_path ;
	string boundary_shp_path;
	date starting_date ;

    gtfs_file gtfs_f <- gtfs_file(gtfs_f_path);
    shape_file boundary_shp <- shape_file(boundary_shp_path);
    geometry shape <- envelope(boundary_shp);
    float step <- 0.2 #s;
    
    // Paramètres génériques anti-saut
    bool enable_anti_jump <- true;
    float jump_detection_threshold <- 150.0 #m;
    float waypoint_spacing <- 25.0 #m;
    int max_navigation_attempts <- 2;
    bool preventive_waypoints <- true;
    
    // Variables GTFS
    string selected_trip_id <- "";
    int selected_bus_stop ;
    bus_stop starts_stop;
    list<bus_stop> list_bus_stops;
    string shape_id;
    
    // Variables pour navigation
    graph selected_clean_network;
    geometry original_shape_polyline;

    init {
        write "=== SYSTÈME GÉNÉRIQUE ANTI-SAUT ===";
        
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;
        
        write "1. Données GTFS chargées: " + string(length(transport_shape)) + " shapes";

        // ÉTAPE 2: Configuration trip
        starts_stop <- bus_stop[selected_bus_stop];
        write sample(selected_bus_stop);
        write sample(starts_stop);
        write "2. Configuration trip " + selected_trip_id;

        write starts_stop.tripShapeMap;

        if (selected_trip_id in starts_stop.tripShapeMap.keys and 
            selected_trip_id in starts_stop.departureStopsInfo.keys) {
            
            shape_id <- starts_stop.tripShapeMap[selected_trip_id];            
            write "   Shape ID: " + string(shape_id);
            
            // Configuration arrêts
            list<pair<bus_stop, string>> stops_for_trip <- starts_stop.departureStopsInfo[selected_trip_id];
            list_bus_stops <- stops_for_trip collect (each.key);
            
            loop i from: 0 to: length(list_bus_stops) - 1 {
                bus_stop stop <- list_bus_stops[i];
                stop.is_in_selected_trip <- true;
                stop.stop_order <- i;
            }

            // ÉTAPE 3: Récupérer polyline originale
            loop s over: transport_shape {
                if (s.shapeId = shape_id and s.shape != nil) {
                    original_shape_polyline <- s.shape;
                    write "3. Polyline récupérée: " + string(length(original_shape_polyline.points)) + " points";
                    break;
                }
            }
            
            // ÉTAPE 4: Configuration réseau (simplifié - sans clean_network)
            selected_clean_network <- as_edge_graph([original_shape_polyline]);
            write "4. Réseau shape: " + string(length(selected_clean_network.edges)) + " arêtes";

            // ÉTAPE 5: Analyse segments
            do analyze_segments_generically;

            // ÉTAPE 6: Créer bus
            if (length(list_bus_stops) >= 2) {
                create bus with: [
                    my_stops:: list_bus_stops,
                    current_index:: 0,
                    location:: list_bus_stops[0].location,
                    next_target:: list_bus_stops[1].location,
                    at_terminus:: false
                ];
                write "5. Bus créé avec système anti-saut générique";
            }
        } else {
            write "✗ Trip non valide";
        }
        
        write "=== SYSTÈME ANTI-SAUT ACTIVÉ ===";
    }
    
    // Analyse générique des segments
    action analyze_segments_generically {
        if (length(list_bus_stops) < 2) {
            return;
        }
        
        write "4.1. Analyse générique des segments:";
        int potentially_problematic <- 0;
        
        loop i from: 0 to: length(list_bus_stops) - 2 {
            bus_stop current_stop <- list_bus_stops[i];
            bus_stop next_stop <- list_bus_stops[i + 1];
            float direct_distance <- current_stop.location distance_to next_stop.location;
            
            if (direct_distance > jump_detection_threshold) {
                potentially_problematic <- potentially_problematic + 1;
                write "   ⚠️ Segment " + string(i+1) + "→" + string(i+2) + ": " + 
                      string(round(direct_distance)) + "m (potentiel saut)";
            }
        }
        
        write "   Segments longs détectés: " + string(potentially_problematic);
        
        // PRÉVENTION: Activer waypoints pour segments longs dès le départ
        if (potentially_problematic > 0 and preventive_waypoints) {
            write "   🛡️ Activation préventive des waypoints pour segments longs";
        }
    }
}

species bus_stop skills: [TransportStopSkill] {
	map<string, string> tripShapeMap;
	string name;

    bool is_in_selected_trip <- false;
    int stop_order <- -1;
    
    aspect base {
        if (is_in_selected_trip) {
            draw circle(25) color: #blue;
            if (stop_order >= 0) {
                draw string(stop_order + 1) color: #white font: font("Arial", 12, #bold) at: location;
            }
            draw name color: #black font: font("Arial", 9, #bold) at: location + {0, 35};
        }
    }
}

species transport_shape skills: [TransportShapeSkill] {
    aspect default {
        if (shapeId = shape_id) {
            draw shape color: #purple width: 6;
        } else {
            draw shape color: #gray width: 1;
        }
    }
}

species bus skills: [moving] {
    list<bus_stop> my_stops;
    int current_index <- 0;
    point next_target;
    bool at_terminus <- false;
    
    // Paramètres mouvement
    float base_speed <- 8.0 #km/#h;
    float current_speed <- 0.0;
    
    // Système anti-saut générique
    list<point> current_waypoints;
    int waypoint_index <- 0;
    bool using_waypoints <- false;
    int navigation_attempts <- 0;
    point last_successful_location;
    
    // Statistiques
    int network_moves <- 0;
    int waypoint_moves <- 0;
    int direct_moves <- 0;
    int anti_jump_activations <- 0;
    float total_distance_traveled <- 0.0;

    reflex navigation when: !at_terminus {
        float distance_to_target <- location distance_to next_target;
        
        if (distance_to_target <= 15#m) {
            do arrive_at_stop;
        } else {
            current_speed <- base_speed;
            bool movement_successful <- false;
            point previous_location <- location;
            last_successful_location <- location;
            
            // PRÉVENTION: Activer waypoints automatiquement pour segments longs
            if (!using_waypoints and preventive_waypoints and current_index < length(my_stops)) {
                bus_stop current_stop <- my_stops[max(0, current_index - 1)];
                bus_stop next_stop <- my_stops[current_index];
                float segment_distance <- current_stop.location distance_to next_stop.location;
                
                if (segment_distance > jump_detection_threshold) {
                    write "🛡️ PRÉVENTION: Activation waypoints pour segment long (" + string(round(segment_distance)) + "m)";
                    do activate_anti_jump_system;
                    anti_jump_activations <- anti_jump_activations + 1;
                }
            }
            
            // ÉTAPE 1: Si utilisation waypoints, continuer
            if (using_waypoints) {
                do navigate_with_waypoints;
                movement_successful <- true;
            } else {
                // ÉTAPE 2: Essayer navigation réseau avec vérification
                if (selected_clean_network != nil) {
                    path network_path <- path_between(selected_clean_network, location, next_target);
                    if (network_path != nil and length(network_path.edges) > 0) {
                        // Vérifier que le chemin n'est pas trop long
                        float path_length <- network_path.shape.perimeter;
                        float direct_distance <- location distance_to next_target;
                        
                        if (path_length > direct_distance * 3.0) {
                            write "⚠️ Chemin réseau trop long, activation waypoints préventive";
                            do activate_anti_jump_system;
                            do navigate_with_waypoints;
                        } else {
                            do goto target: next_target on: selected_clean_network speed: current_speed;
                            network_moves <- network_moves + 1;
                        }
                        movement_successful <- true;
                        navigation_attempts <- 0;
                    }
                }
                
                // ÉTAPE 3: Navigation directe avec détection saut améliorée
                if (!movement_successful) {
                    float distance_before <- location distance_to next_target;
                    
                    // Si distance initiale grande, activer waypoints préventivement
                    if (distance_before > jump_detection_threshold and enable_anti_jump) {
                        write "🛡️ PRÉVENTION: Distance importante détectée (" + string(round(distance_before)) + "m)";
                        do activate_anti_jump_system;
                        do navigate_with_waypoints;
                        movement_successful <- true;
                    } else {
                        do goto target: next_target speed: current_speed;
                        float distance_after <- location distance_to next_target;
                        float movement_distance <- previous_location distance_to location;
                        
                        // DÉTECTION SAUT AMÉLIORÉE
                        bool jumped <- detect_jump_enhanced(previous_location, location, movement_distance, distance_before);
                        
                        if (jumped and enable_anti_jump) {
                            write "🚨 SAUT DÉTECTÉ! Retour et activation waypoints";
                            location <- last_successful_location;
                            do activate_anti_jump_system;
                            anti_jump_activations <- anti_jump_activations + 1;
                        } else {
                            direct_moves <- direct_moves + 1;
                            movement_successful <- true;
                            navigation_attempts <- 0;
                        }
                    }
                }
            }
            
            // Mettre à jour distance parcourue
            if (movement_successful) {
                total_distance_traveled <- total_distance_traveled + (previous_location distance_to location);
            }
        }
    }
    
    // Détection améliorée de saut avec critères plus stricts
    bool detect_jump_enhanced(point from_pos, point to_pos, float movement_dist, float target_dist) {
        // Critère 1: Mouvement anormalement long (seuil réduit)
        if (movement_dist > jump_detection_threshold * 0.7) {
            write "   → Saut détecté: mouvement trop long (" + string(round(movement_dist)) + "m)";
            return true;
        }
        
        // Critère 2: Vitesse de déplacement irréaliste
        float max_realistic_speed <- base_speed * 2.0;
        float time_step <- step;
        float apparent_speed <- movement_dist / (time_step * 3600);
        
        if (apparent_speed > max_realistic_speed) {
            write "   → Saut détecté: vitesse irréaliste (" + string(round(apparent_speed * 3.6)) + " km/h)";
            return true;
        }
        
        // Critère 3: Direction opposée (vérifie si on s'éloigne de la cible)
        if (movement_dist > 20 and target_dist > 20) {
            float distance_after <- to_pos distance_to next_target;
            float delta_distance <- distance_after - target_dist;
            
            if (delta_distance > 0 and delta_distance > movement_dist * 0.5) {
                write "   → Saut détecté: mouvement s'éloigne de la cible";
                return true;
            }
        }
        
        // Critère 4: Angle trop important
        if (movement_dist > 50 and target_dist > 50) {
            float angle_to_target <- from_pos towards next_target;
            float angle_moved <- from_pos towards to_pos;
            float angle_diff <- abs(angle_to_target - angle_moved);
            if (angle_diff > 180) {
                angle_diff <- 360 - angle_diff;
            }
            
            if (angle_diff > 90 and movement_dist > 50) {
                write "   → Saut détecté: direction opposée (" + string(round(angle_diff)) + "°)";
                return true;
            }
        }
        
        return false;
    }
    
    // Activation du système anti-saut
    action activate_anti_jump_system {
        using_waypoints <- true;
        waypoint_index <- 0;
        current_waypoints <- [];
        
        // Générer waypoints basés sur la polyline si disponible
        if (original_shape_polyline != nil) {
            do generate_polyline_waypoints;
        } else {
            do generate_linear_waypoints;
        }
        
        write "   Waypoints générés: " + string(length(current_waypoints));
    }
    
    // Générer waypoints basés sur la polyline avec plus de densité
    action generate_polyline_waypoints {
        if (original_shape_polyline = nil) {
            return;
        }
        
        list<point> polyline_points <- original_shape_polyline.points;
        point current_pos <- location;
        point target_pos <- next_target;
        
        // Trouver point polyline le plus proche de la position actuelle
        int start_index <- 0;
        float min_dist <- 999999.0;
        loop i from: 0 to: length(polyline_points) - 1 {
            float dist <- current_pos distance_to polyline_points[i];
            if (dist < min_dist) {
                min_dist <- dist;
                start_index <- i;
            }
        }
        
        // Trouver point polyline le plus proche de la cible
        int end_index <- length(polyline_points) - 1;
        min_dist <- 999999.0;
        loop i from: start_index to: length(polyline_points) - 1 {
            float dist <- target_pos distance_to polyline_points[i];
            if (dist < min_dist) {
                min_dist <- dist;
                end_index <- i;
            }
        }
        
        // Créer waypoints plus denses pour éviter les sauts
        int step <- max(1, int(waypoint_spacing / 15));
        loop i from: start_index to: end_index step: step {
            current_waypoints <- current_waypoints + [polyline_points[i]];
        }
        
        // Si pas assez de waypoints, en créer plus par interpolation
        if (length(current_waypoints) < 3) {
            current_waypoints <- [];
            float total_polyline_distance <- 0.0;
            loop i from: start_index to: end_index - 1 {
                total_polyline_distance <- total_polyline_distance + 
                    (polyline_points[i] distance_to polyline_points[i + 1]);
            }
            
            int needed_waypoints <- int(total_polyline_distance / waypoint_spacing) + 1;
            needed_waypoints <- max(3, min(needed_waypoints, 15));
            
            loop j from: 0 to: needed_waypoints - 1 {
                float ratio <- j / (needed_waypoints - 1);
                int polyline_index <- start_index + int(ratio * (end_index - start_index));
                polyline_index <- max(start_index, min(polyline_index, end_index));
                current_waypoints <- current_waypoints + [polyline_points[polyline_index]];
            }
        }
        
        // Ajouter la cible finale
        if (length(current_waypoints) = 0 or 
            current_waypoints[length(current_waypoints) - 1] distance_to target_pos > 15) {
            current_waypoints <- current_waypoints + [target_pos];
        }
        
        write "   Waypoints polyline générés: " + string(length(current_waypoints));
    }
    
    // Générer waypoints linéaires
    action generate_linear_waypoints {
        point current_pos <- location;
        point target_pos <- next_target;
        float total_distance <- current_pos distance_to target_pos;
        
        int nb_waypoints <- int(total_distance / waypoint_spacing);
        nb_waypoints <- max(2, min(nb_waypoints, 20));
        
        loop i from: 1 to: nb_waypoints {
            float ratio <- i / nb_waypoints;
            point waypoint <- {
                current_pos.x + ratio * (target_pos.x - current_pos.x),
                current_pos.y + ratio * (target_pos.y - current_pos.y)
            };
            current_waypoints <- current_waypoints + [waypoint];
        }
    }
    
    // Navigation avec waypoints
    action navigate_with_waypoints {
        if (length(current_waypoints) = 0 or waypoint_index >= length(current_waypoints)) {
            using_waypoints <- false;
            return;
        }
        
        point current_waypoint <- current_waypoints[waypoint_index];
        float distance_to_waypoint <- location distance_to current_waypoint;
        
        if (distance_to_waypoint <= 10#m) {
            waypoint_index <- waypoint_index + 1;
            if (waypoint_index >= length(current_waypoints)) {
                using_waypoints <- false;
                write "   ✅ Waypoints terminés, retour navigation normale";
            }
        } else {
            do goto target: current_waypoint speed: current_speed;
            waypoint_moves <- waypoint_moves + 1;
        }
    }
    
    // Arriver à un arrêt
    action arrive_at_stop {
        location <- next_target;
        using_waypoints <- false;
        current_waypoints <- [];
        navigation_attempts <- 0;
        
        if (current_index >= 0 and current_index < length(my_stops)) {
            bus_stop current_stop <- my_stops[current_index];
            write "🚌 Arrêt " + string(current_index + 1) + "/" + string(length(my_stops)) + ": " + current_stop.name;
            
            current_index <- current_index + 1;
            
            if (current_index < length(my_stops)) {
                next_target <- my_stops[current_index].location;
                write "➡️ Prochain: " + my_stops[current_index].name;
            } else {
                write "🏁 TERMINUS! Stats système anti-saut:";
                write "   - Réseau: " + string(network_moves);
                write "   - Waypoints: " + string(waypoint_moves);
                write "   - Direct: " + string(direct_moves);
                write "   - Activations anti-saut: " + string(anti_jump_activations);
                
                int total_moves <- network_moves + waypoint_moves + direct_moves;
                if (total_moves > 0) {
                    float waypoint_ratio <- waypoint_moves / total_moves * 100;
                    write "📊 Utilisation waypoints: " + string(round(waypoint_ratio)) + "%";
                }
                write "📏 Distance: " + string(round(total_distance_traveled)) + "m";
                
                at_terminus <- true;
            }
        } else {
            at_terminus <- true;
        }
    }
    
    aspect base {
        rgb bus_color <- at_terminus ? #orange : #red;
        draw rectangle(200, 120) color: bus_color rotate: heading;
        
        string display_text <- at_terminus ? "TERMINÉ" : string(current_index + 1) + "/" + string(length(my_stops));
        draw display_text color: #white font: font("Arial", 12, #bold) at: location + {0, -40};
        
        // Mode navigation
        string nav_mode <- using_waypoints ? "ANTI-JUMP" : 
                          (network_moves > direct_moves ? "NETWORK" : "DIRECT");
        draw nav_mode color: #blue font: font("Arial", 9, #bold) at: location + {0, -60};
        
        // Vitesse
        draw "V: " + string(round(current_speed * 3.6)) + "km/h" color: #green 
             font: font("Arial", 8, #bold) at: location + {0, -80};
        
        if (!at_terminus) {
            // Ligne vers cible actuelle
            point actual_target <- using_waypoints and length(current_waypoints) > waypoint_index ? 
                                 current_waypoints[waypoint_index] : next_target;
            if (actual_target != nil) {
                draw line([location, actual_target]) color: #blue width: 3;
            }
            
            // Visualiser waypoints actifs
            if (using_waypoints and length(current_waypoints) > 0) {
                loop i from: waypoint_index to: length(current_waypoints) - 1 {
                    draw circle(8) color: #yellow at: current_waypoints[i];
                    if (i < length(current_waypoints) - 1) {
                        draw line([current_waypoints[i], current_waypoints[i + 1]]) color: #yellow width: 2;
                    }
                }
            }
        }
    }    
}

experiment MoveOnTripOfDepartureStopsInfor type: gui virtual: true {
    parameter "Système anti-saut" var: enable_anti_jump;
    parameter "Seuil détection saut (m)" var: jump_detection_threshold min: 50.0 max: 300.0;
    parameter "Espacement waypoints (m)" var: waypoint_spacing min: 10.0 max: 50.0;
    parameter "Waypoints préventifs" var: preventive_waypoints;
    
    output {
        display "Navigation Anti-Saut" {
            species bus_stop aspect: base;
            species transport_shape aspect: default;
            species bus aspect: base;
        }
        
        monitor "Arêtes réseau shape" value: selected_clean_network != nil ? length(selected_clean_network.edges) : 0;
        monitor "Seuil saut (m)" value: jump_detection_threshold;
        monitor "Mouvements réseau" value: length(bus) > 0 ? first(bus).network_moves : 0;
        monitor "Mouvements waypoints" value: length(bus) > 0 ? first(bus).waypoint_moves : 0;
        monitor "Mouvements directs" value: length(bus) > 0 ? first(bus).direct_moves : 0;
        monitor "Activations anti-saut" value: length(bus) > 0 ? first(bus).anti_jump_activations : 0;
        monitor "Utilise waypoints" value: length(bus) > 0 ? first(bus).using_waypoints : false;
        monitor "Waypoints actifs" value: length(bus) > 0 ? length(first(bus).current_waypoints) : 0;
        monitor "Distance parcourue" value: length(bus) > 0 ? first(bus).total_distance_traveled : 0;
        monitor "Trip ID" value: selected_trip_id;
        monitor "Shape ID" value: shape_id;
    }
}


experiment testDepartureStopsInforToulouse type: gui parent: MoveOnTripOfDepartureStopsInfor {
	parameter "GTFS file path" var: gtfs_f_path <- "../../includes/tisseo_gtfs_v2";	
	parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileToulouse.shp";
	parameter "Starting date" var: starting_date <- date("2025-06-09T16:00:00");
	
	parameter "Selected Trip ID" var: selected_trip_id <- "2076784";
	parameter "Selected bus stop" var: selected_bus_stop <- 2474; 
	
}

experiment testDepartureStopsInforNantes type: gui parent: MoveOnTripOfDepartureStopsInfor {
	parameter "GTFS file path" var: gtfs_f_path <- "../../includes/nantes_gtfs";	
	parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileNantes.shp";
	parameter "Starting date" var: starting_date <- date("2025-05-15T00:55:00");
	
	parameter "Selected Trip ID" var: selected_trip_id <- "44958927-CR_24_25-HT25P201-L-Ma-Me-J-11";
	parameter "Selected bus stop" var: selected_bus_stop <- 2540; 

}

experiment testDepartureStopsInforHanoi type: gui parent: MoveOnTripOfDepartureStopsInfor {
	parameter "GTFS file path" var: gtfs_f_path <- "../../includes/hanoi_gtfs_pm";	
	parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileHanoishp.shp";
	parameter "Starting date" var: starting_date <- date("2018-01-01T20:55:00");
	
	parameter "Selected Trip ID" var: selected_trip_id <- "01_1_MD_1";
	parameter "Selected bus stop" var: selected_bus_stop <- 0; 
	
}
