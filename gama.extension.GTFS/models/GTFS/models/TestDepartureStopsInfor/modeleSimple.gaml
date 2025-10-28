model MoveOnTripSimple

global {
	// Path to the GTFS file
	string gtfs_f_path;
	string boundary_shp_path;
	date starting_date;

    gtfs_file gtfs_f <- gtfs_file(gtfs_f_path);
    shape_file boundary_shp <- shape_file(boundary_shp_path);
    geometry shape <- envelope(boundary_shp);
    float step <- 0.2 #s;
    
    // Variables GTFS
    string selected_trip_id <- "";
    int selected_bus_stop;
    bus_stop starts_stop;
    list<bus_stop> list_bus_stops;
    string shape_id;

    init {
        write "=== MODÈLE SIMPLE DE DÉPLACEMENT ===";
        
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;
        
        write "1. Données GTFS chargées: " + string(length(transport_shape)) + " shapes";

        // Configuration trip
        starts_stop <- bus_stop[selected_bus_stop];
        write "2. Configuration trip " + selected_trip_id;

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

            // Créer bus
            if (length(list_bus_stops) >= 2) {
                create bus with: [
                    my_stops:: list_bus_stops,
                    current_index:: 0,
                    next_target:: list_bus_stops[1].location,
                    at_terminus:: false
                ];
                write "3. Bus créé";
            }
        } else {
            write "✗ Trip non valide";
        }
        
        write "=== DÉMARRAGE SIMULATION ===";
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
    float speed <- 1.0 #km/#h;
    float total_distance_traveled <- 0.0;
    
    // Variables pour navigation polyline
    list<point> travel_points;
    int travel_idx <- 0;
    point moving_target;
    bool is_moving <- false;
    float close_dist <- 5.0 #m;
    
    init {
        // Récupérer la polyline du trip
        loop s over: transport_shape {
            if (s.shapeId = shape_id and s.shape != nil) {
                travel_points <- s.shape.points;
                
                // IMPORTANT : Démarrer au premier point de la polyline
                if (length(travel_points) > 0) {
                    location <- travel_points[0];
                    write "   Position départ: premier point polyline (" + string(length(travel_points)) + " points total)";
                }
                break;
            }
        }
    }

    // Reflex 1 : Mouvement vers le point cible
    reflex move when: is_moving {
        point previous_location <- location;
        
        // Navigation DIRECTE (pas de réseau - c'est la clé !)
        do goto target: moving_target speed: speed;
        
        // Mettre à jour distance parcourue
        total_distance_traveled <- total_distance_traveled + (previous_location distance_to location);
        
        // Vérifier si on a atteint le point (snap pour éviter dérive)
        if (location distance_to moving_target < close_dist) {
            location <- moving_target;  // Snap exact
            is_moving <- false;
        }
    }
    
    // Reflex 2 : Calcul du prochain point à atteindre
    reflex follow_route when: !is_moving and !at_terminus {
        // PROTECTION : Vérifier si on est au dernier arrêt
        if (current_index >= length(my_stops) - 1) {
            if (location distance_to next_target <= 15#m) {
                do arrive_at_stop;
            }
            return;  // Ne pas continuer après le terminus
        }
        
        float distance_to_target <- location distance_to next_target;
        
        // Vérifier si on est arrivé à l'arrêt
        if (distance_to_target <= 15#m) {
            do arrive_at_stop;
        } else {
            // Trouver le prochain point de la polyline
            if (length(travel_points) > 0 and travel_idx < length(travel_points) - 1) {
                travel_idx <- travel_idx + 1;
                moving_target <- travel_points[travel_idx];
                is_moving <- true;
            } else {
                // Plus de points polyline → aller direct à l'arrêt
                moving_target <- next_target;
                is_moving <- true;
            }
        }
    }
    
    // Arriver à un arrêt
    action arrive_at_stop {
        location <- next_target;
        is_moving <- false;
        
        if (current_index >= 0 and current_index < length(my_stops)) {
            bus_stop current_stop <- my_stops[current_index];
            write "🚌 Arrêt " + string(current_index + 1) + "/" + string(length(my_stops)) + ": " + current_stop.name;
            
            current_index <- current_index + 1;
            
            if (current_index < length(my_stops)) {
                next_target <- my_stops[current_index].location;
                write "➡️ Prochain: " + my_stops[current_index].name;
                
                // Trouver l'index du point polyline le plus proche du nouvel arrêt
                if (length(travel_points) > 0) {
                    float min_dist <- 999999.0;
                    loop i from: travel_idx to: length(travel_points) - 1 {
                        float dist <- next_target distance_to travel_points[i];
                        if (dist < min_dist) {
                            min_dist <- dist;
                            travel_idx <- i;
                        }
                    }
                }
            } else {
                write "🏁 TERMINUS!";
                write "📏 Distance: " + string(round(total_distance_traveled)) + "m";
                at_terminus <- true;
                next_target <- nil;
                moving_target <- nil;
            }
        } else {
            at_terminus <- true;
            next_target <- nil;
            moving_target <- nil;
        }
    }
    
    aspect base {
        rgb bus_color <- at_terminus ? #orange : #red;
        draw rectangle(200, 120) color: bus_color rotate: heading;
        
        string display_text <- at_terminus ? "TERMINÉ" : string(current_index + 1) + "/" + string(length(my_stops));
        draw display_text color: #white font: font("Arial", 12, #bold) at: location + {0, -40};
        
        // Vitesse
        draw "V: " + string(round(speed * 3.6)) + "km/h" color: #green 
             font: font("Arial", 8, #bold) at: location + {0, -60};
        
        // Ligne vers point cible actuel (bleu)
        if (!at_terminus and moving_target != nil and is_moving) {
            draw line([location, moving_target]) color: #blue width: 3;
        }
    }
}

experiment MoveOnTripSimple type: gui virtual: true {
    output {
        display "Navigation Simple" {
            species bus_stop aspect: base;
            species transport_shape aspect: default;
            species bus aspect: base;
        }
        
        monitor "Distance parcourue (m)" value: length(bus) > 0 ? round(first(bus).total_distance_traveled) : 0;
        monitor "Arrêt actuel" value: length(bus) > 0 ? first(bus).current_index + 1 : 0;
        monitor "Points polyline restants" value: length(bus) > 0 ? (length(first(bus).travel_points) - first(bus).travel_idx) : 0;
        monitor "Trip ID" value: selected_trip_id;
        monitor "Shape ID" value: shape_id;
    }
}

experiment testSimpleToulouse type: gui parent: MoveOnTripSimple {
	parameter "GTFS file path" var: gtfs_f_path <- "../../includes/tisseo_gtfs_v2";	
	parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileToulouse.shp";
	parameter "Starting date" var: starting_date <- date("2025-06-09T16:00:00");
	
	parameter "Selected Trip ID" var: selected_trip_id <- "2076784";
	parameter "Selected bus stop" var: selected_bus_stop <- 2474;
}

experiment testSimpleNantes type: gui parent: MoveOnTripSimple {
	parameter "GTFS file path" var: gtfs_f_path <- "../../includes/nantes_gtfs";	
	parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileNantes.shp";
	parameter "Starting date" var: starting_date <- date("2025-05-15T00:55:00");
	
	parameter "Selected Trip ID" var: selected_trip_id <- "44958927-CR_24_25-HT25P201-L-Ma-Me-J-11";
	parameter "Selected bus stop" var: selected_bus_stop <- 2540;
}

experiment testSimpleHanoi type: gui parent: MoveOnTripSimple {
	parameter "GTFS file path" var: gtfs_f_path <- "../../includes/hanoi_gtfs_pm";	
	parameter "Boundary shapefile" var: boundary_shp_path <- "../../includes/shapeFileHanoishp.shp";
	parameter "Starting date" var: starting_date <- date("2018-01-01T20:55:00");
	
	parameter "Selected Trip ID" var: selected_trip_id <- "01_1_MD_1";
	parameter "Selected bus stop" var: selected_bus_stop <- 0;
}
