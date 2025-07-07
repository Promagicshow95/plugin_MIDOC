model Moving_Trip_Snapped_Enhanced

global {
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
    shape_file boundary_shp <- shape_file("../../includes/ShapeFileToulouse.shp");
    geometry shape <- envelope(boundary_shp);
    map<int, graph> shape_graphs;
    string selected_trip_id <- "2039311"; // Trip ID à modifier selon le trip voulu
    int shape_id;
    graph shape_network;
    list<pair<bus_stop, string>> departureStopsInfo;
    list<bus_stop> list_bus_stops;
    list<point> snapped_locations;
    bus_stop starts_stop;
    int current_seconds_mod <- 0;
    date starting_date <- date("2025-06-09T16:00:00");
    float step <- 0.2 #s;

    init {
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;

        // Crée les graphes à partir de la liste de segments (méthode recommandée)
        loop s over: transport_shape {
            if (s.shape != nil and length(s.shape.points) > 1) {
                list<geometry> segments <- [];
                loop i from: 0 to: length(s.shape.points) - 2 {
                    segments <- segments + line([s.shape.points[i], s.shape.points[i+1]]);
                }
                shape_graphs[s.shapeId] <- as_edge_graph(segments);
            }
        }

        // Choisir un arrêt spécifique (comme dans votre modèle original)
        starts_stop <- bus_stop[1765];
        
        // Vérification que l'arrêt existe
        if (starts_stop = nil) {
            write "❌ Erreur: Arrêt à l'index 1765 non trouvé";
            return;
        }

        // Récupérer shape_id et shape_network pour le trip sélectionné
        if (starts_stop.tripShapeMap = nil or not(starts_stop.tripShapeMap contains_key selected_trip_id)) {
            write "❌ Erreur: Trip ID '" + selected_trip_id + "' non trouvé dans tripShapeMap";
            write "🔍 Trips disponibles: " + starts_stop.tripShapeMap.keys;
            return;
        }
        
        shape_id <- starts_stop.tripShapeMap[selected_trip_id];
        write "✅ Shape ID récupéré directement : " + shape_id;
        
        if (shape_graphs = nil or not(shape_graphs contains_key shape_id)) {
            write "❌ Erreur: Shape ID '" + shape_id + "' non trouvé dans shape_graphs";
            write "🔍 Shapes disponibles: " + shape_graphs.keys;
            return;
        }
        
        shape_network <- shape_graphs[shape_id];

        // Liste des arrêts du trip sélectionné (ordre de passage)
        if (starts_stop.departureStopsInfo = nil or not(starts_stop.departureStopsInfo contains_key selected_trip_id)) {
            write "❌ Erreur: Pas d'info d'arrêts pour le trip '" + selected_trip_id + "'";
            return;
        }
        
        list<pair<bus_stop, string>> stops_for_trip <- starts_stop.departureStopsInfo[selected_trip_id];
        
        if (length(stops_for_trip) = 0) {
            write "❌ Erreur: Liste d'arrêts vide pour le trip '" + selected_trip_id + "'";
            return;
        }
        
        list_bus_stops <- stops_for_trip collect (each.key);
        write "✅ Liste des arrêts du bus : " + list_bus_stops;
        write "✅ DepartureStopsInfo à donner au bus : " + stops_for_trip;
        write "✅ Taille de la liste : " + length(stops_for_trip);

        // Marquer les arrêts qui font partie du trip sélectionné
        loop stop over: list_bus_stops {
            stop.is_on_selected_trip <- true;
        }

        // Liste de points du shape utilisé pour le snapping
        list<point> shape_points <- [];
        loop shape_elem over: transport_shape where (each.shapeId = shape_id) {
            if (shape_elem.shape != nil) {
                shape_points <- shape_points + shape_elem.shape.points;
            }
        }
        
        if (length(shape_points) = 0) {
            write "❌ Erreur: Aucun point trouvé pour le shape " + shape_id;
            return;
        }
        
        write "✅ Nombre de points du shape: " + length(shape_points);

        // Snap automatique : pour chaque bus_stop du trip, trouver le point du shape le plus proche
        snapped_locations <- [];
        loop stop over: list_bus_stops {
            if (stop != nil and stop.location != nil) {
                point snapped_pt <- closest_to(shape_points, stop.location);
                snapped_locations <- snapped_locations + snapped_pt;
            } else {
                write "⚠️ Arrêt ou location nil détecté";
            }
        }
        
        write "✅ Nombre de positions snappées: " + length(snapped_locations);
        
        // Vérification que nous avons le même nombre d'arrêts et de positions snappées
        if (length(list_bus_stops) != length(snapped_locations)) {
            write "❌ Erreur: Nombre d'arrêts (" + length(list_bus_stops) + ") != nombre de positions snappées (" + length(snapped_locations) + ")";
            return;
        }

        // On met à jour la location des stops utilisés vers les positions snappées
        loop i from: 0 to: length(list_bus_stops) - 1 {
            if (i < length(list_bus_stops) and i < length(snapped_locations)) {
                bus_stop stop <- list_bus_stops[i];
                if (stop != nil) {
                    stop.location <- snapped_locations[i];
                }
            }
        }

        // Construction des paires arrêt + heure en utilisant les positions snappées
        list<pair<bus_stop, string>> snapped_departureStopsInfo <- [];
        loop i from: 0 to: length(list_bus_stops) - 1 {
            if (i < length(list_bus_stops) and i < length(stops_for_trip)) {
                snapped_departureStopsInfo <- snapped_departureStopsInfo + pair(list_bus_stops[i], stops_for_trip[i].value);
            }
        }
        
        // Vérification avant création du bus
        if (length(snapped_locations) < 2) {
            write "❌ Erreur: Pas assez de positions snappées pour créer un trajet (minimum 2 requis)";
            return;
        }

        // Création du bus : il suivra les arrêts snappés sur le shape
        create bus with: [
            my_departureStopsInfo:: snapped_departureStopsInfo,
            current_stop_index:: 0,
            location:: snapped_locations[0],
            target_location:: snapped_locations[1],
            start_time:: int(cycle * step / #s)
        ];
        
        write "✅ Bus créé avec succès pour le trip " + selected_trip_id;
    }
}

species bus_stop skills: [TransportStopSkill] {
    rgb customColor <- rgb(0,0,255);
    map<string, int> tripShapeMap; // Clé=tripId, Valeur=shapeId
    string name; // Nom de l'arrêt
    bool is_on_selected_trip <- false; // Indique si cet arrêt fait partie du trip sélectionné
    
    aspect base {
        draw circle(20) color: customColor;
        // Afficher le nom de l'arrêt s'il fait partie du trip sélectionné
        if (is_on_selected_trip and name != nil) {
            draw name color: #black font: font("Arial", 12, #bold) at: location + {0, 25};
        }
    }
}

species transport_shape skills: [TransportShapeSkill] {
    aspect default {
        // Afficher seulement le polyline (shape) que le bus va emprunter
        if (shapeId = shape_id) {
            draw shape color: #green width: 3;
        }
    }
}

species bus skills: [moving] {
    aspect base {
        draw rectangle(200, 100) color: #red rotate: heading;
    }

    list<pair<bus_stop, string>> my_departureStopsInfo;
    int current_stop_index <- 0;
    point target_location;
    int start_time;
    float speed <- 10.0 #km/#h; // Vitesse du bus

    init {
        write "✅ Bus créé avec my_departureStopsInfo : " + my_departureStopsInfo;
        departureStopsInfo <- my_departureStopsInfo;
    }

    reflex move when: self.location distance_to target_location > 5#m {
        do goto target: target_location on: shape_network speed: speed;
        if location distance_to target_location < 5#m {
            location <- target_location;
        }
    }

    reflex check_arrival when: self.location = target_location {
        // Afficher le nom de l'arrêt où le bus est arrivé
        string stop_name <- departureStopsInfo[current_stop_index].key.name;
        string departure_time <- departureStopsInfo[current_stop_index].value;
        write "🚌 Bus arrivé à l'arrêt : " + stop_name + " (index: " + current_stop_index + ") à " + departure_time;

        if (current_stop_index < length(departureStopsInfo) - 1) {
            current_stop_index <- current_stop_index + 1;
            target_location <- departureStopsInfo[current_stop_index].key.location;

            // Afficher le prochain arrêt
            string next_stop_name <- departureStopsInfo[current_stop_index].key.name;
            string next_departure_time <- departureStopsInfo[current_stop_index].value;
            write "🚌 Bus se dirige vers : " + next_stop_name + " (départ prévu: " + next_departure_time + ")";
        } else {
            write "🚌 Bus arrivé au terminus !";
            do die;
        }
    }
}

experiment GTFSExperiment type: gui {
    output {
        display "Bus Simulation" {
            species bus_stop aspect: base refresh: true;
            species bus aspect: base;
            species transport_shape aspect: default;
        }
    }
}