/**
 * Name: Network_Bus_Complete
 * Description: Construction du graphe bus + Analyse connectivité + Export
 * Tags: shapefile, network, bus, graph, export, connectivity
 * Date: 2025-10-02
 */

model Network_Bus_Complete

global {
    // --- CONFIGURATION FICHIERS ---
    string results_folder <- "../../results/";
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // --- CONFIGURATION GRAPHE ---
    float SNAP_TOL <- 6.0;
    graph road_graph;
    map<point, int> node_ids <- [];
    map<int, point> G_NODES <- [];
    map<int, list<int>> G_ADJ <- [];
    list<list<int>> edges_list <- [];
    int node_counter <- 0;
    
    // --- MAPPING EDGES - ROUTES ---
    map<list<int>, int> EDGE_KEY_TO_ID <- [];
    map<int, list<string>> EDGE_TO_ROUTES <- [];
    map<string, list<int>> ROUTE_TO_EDGES <- [];
    list<float> EDGE_LENGTHS <- [];
    
    // --- DIAGNOSTICS CONNECTIVITE ---
    int nb_components <- 0;
    int nb_dead_ends <- 0;
    float avg_degree <- 0.0;
    list<int> isolated_nodes <- [];
    list<geometry> test_paths <- [];
    int successful_routes <- 0;
    int failed_routes <- 0;
    
    // --- MODE ---
    bool rebuild_from_osm <- true;

    init {
        write "=== RESEAU BUS COMPLET ===";
        
        if rebuild_from_osm {
            do load_bus_network_robust;
            do validate_world_envelope;
            do build_routable_graph;
            
            // ANALYSE CONNECTIVITE
            do check_connectivity;
            do random_routing_tests(30);
            
            // EXPORT
            do export_graph_files;
        } else {
            do validate_world_envelope;
            do load_graph_from_edges;
        }
        
        // Résumé
        write "\n=== RESUME FINAL ===";
        write "Noeuds graphe : " + length(G_NODES);
        write "Aretes graphe : " + length(edges_list);
        write "Composantes connexes : " + nb_components;
        write "Dead-ends : " + nb_dead_ends;
        write "Degre moyen : " + (avg_degree with_precision 2);
        write "Tests routage : " + successful_routes + "/" + (successful_routes + failed_routes);
        write "Graphe cree : " + (road_graph != nil ? "OK" : "ERREUR");
    }
    
    // CONSTRUCTION DU GRAPHE
    action build_routable_graph {
        write "\n=== CONSTRUCTION GRAPHE ===";
        
        int processed_routes <- 0;
        int valid_segments <- 0;
        
        loop route over: bus_route {
            if route.shape != nil and route.shape.points != nil {
                list<point> points <- route.shape.points;
                
                if length(points) > 1 {
                    processed_routes <- processed_routes + 1;
                    string rid <- route.osm_id;
                    
                    loop i from: 0 to: length(points) - 2 {
                        point p1 <- snap_point(points[i]);
                        point p2 <- snap_point(points[i + 1]);
                        
                        if p1 != p2 {
                            int id1 <- get_or_create_node(p1);
                            int id2 <- get_or_create_node(p2);
                            
                            int a <- min(id1, id2);
                            int b <- max(id1, id2);
                            list<int> ekey <- [a, b];
                            
                            int eid;
                            
                            if (ekey in EDGE_KEY_TO_ID.keys) {
                                eid <- EDGE_KEY_TO_ID[ekey];
                            } else {
                                eid <- length(edges_list);
                                edges_list << ekey;
                                EDGE_KEY_TO_ID[ekey] <- eid;
                                
                                float len <- G_NODES[a] distance_to G_NODES[b];
                                EDGE_LENGTHS << len;
                                
                                if not (b in G_ADJ[a]) { G_ADJ[a] << b; }
                                if not (a in G_ADJ[b]) { G_ADJ[b] << a; }
                                
                                valid_segments <- valid_segments + 1;
                            }
                            
                            if not (eid in EDGE_TO_ROUTES.keys) { 
                                EDGE_TO_ROUTES[eid] <- []; 
                            }
                            if not (rid in EDGE_TO_ROUTES[eid]) { 
                                EDGE_TO_ROUTES[eid] << rid; 
                            }
                            
                            if not (rid in ROUTE_TO_EDGES.keys) { 
                                ROUTE_TO_EDGES[rid] <- []; 
                            }
                            if not (eid in ROUTE_TO_EDGES[rid]) { 
                                ROUTE_TO_EDGES[rid] << eid; 
                            }
                        }
                    }
                }
            }
        }
        
        // Créer le graphe GAMA
        if length(G_NODES) > 0 {
            list<geometry> graph_edges <- [];
            
            loop edge over: edges_list {
                point p1 <- G_NODES[edge[0]];
                point p2 <- G_NODES[edge[1]];
                geometry line_edge <- line([p1, p2]);
                graph_edges << line_edge;
            }
            
            if length(graph_edges) > 0 {
                road_graph <- as_edge_graph(graph_edges);
            }
        }
        
        write "Routes traitees : " + processed_routes;
        write "Aretes uniques : " + valid_segments;
        write "Noeuds crees : " + length(G_NODES);
    }
    
    // ANALYSE CONNECTIVITE
    action check_connectivity {
        write "\n=== ANALYSE CONNECTIVITE ===";
        
        if length(G_NODES) = 0 {
            write "ERREUR: Pas de noeuds dans le graphe";
            return;
        }
        
        // BFS pour composantes connexes
        map<int, int> visited <- [];
        list<list<int>> components <- [];
        
        loop node_id over: G_NODES.keys {
            if not (node_id in visited.keys) {
                list<int> component <- [];
                list<int> queue <- [node_id];
                
                loop while: not empty(queue) {
                    int current <- first(queue);
                    queue >- current;
                    
                    if not (current in visited.keys) {
                        visited[current] <- length(components);
                        component << current;
                        
                        if current in G_ADJ.keys {
                            loop neighbor over: G_ADJ[current] {
                                if not (neighbor in visited.keys) {
                                    queue << neighbor;
                                }
                            }
                        }
                    }
                }
                
                components << component;
            }
        }
        
        nb_components <- length(components);
        
        // Identifier petites composantes
        loop comp over: components {
            if length(comp) < 5 {
                isolated_nodes <- isolated_nodes + comp;
            }
        }
        
        // Analyse des degrés
        int total_degree <- 0;
        loop node_id over: G_NODES.keys {
            int degree <- node_id in G_ADJ.keys ? length(G_ADJ[node_id]) : 0;
            if degree = 1 {
                nb_dead_ends <- nb_dead_ends + 1;
            }
            total_degree <- total_degree + degree;
        }
        
        avg_degree <- length(G_NODES) > 0 ? total_degree / length(G_NODES) : 0.0;
        
        // Créer agents pour visualisation
        loop node_id over: isolated_nodes {
            point node_location <- G_NODES[node_id];
            create graph_issue {
                location <- node_location;
                issue_type <- "isolated";
            }
        }
        
        write "Composantes connexes : " + nb_components;
        write "Noeuds isoles : " + length(isolated_nodes);
        write "Dead-ends : " + nb_dead_ends;
        write "Degre moyen : " + (avg_degree with_precision 2);
        
        if not empty(components) {
            int max_size <- max(components collect length(each));
            float coverage <- (100.0 * max_size / length(G_NODES));
            write "Plus grande composante : " + max_size + " noeuds (" + 
                  (coverage with_precision 1) + "%)";
            
            if nb_components > 1 {
                write "ALERTE: Reseau fragmente en " + nb_components + " composantes";
            }
        }
    }
    
    // TESTS DE ROUTAGE
    action random_routing_tests(int nb) {
        write "\n=== TESTS DE ROUTAGE ===";
        
        if road_graph = nil or length(G_NODES) < 2 {
            write "ERREUR: Graphe insuffisant pour tests";
            return;
        }
        
        list<point> nodes_list <- G_NODES.values;
        
        loop i from: 0 to: nb - 1 {
            point source <- one_of(nodes_list);
            point target <- one_of(nodes_list);
            
            if source != target {
                path test_path <- path_between(road_graph, source, target);
                
                if test_path != nil {
                    successful_routes <- successful_routes + 1;
                    
                    if length(test_paths) < 5 {
                        test_paths << test_path.shape;
                        
                        float path_length <- test_path.shape.perimeter;
                        float euclidean <- source distance_to target;
                        float ratio <- euclidean > 0 ? path_length / euclidean : 0.0;
                        
                        if ratio > 3.0 {
                            write "ATTENTION: Chemin tres indirect (ratio " + (ratio with_precision 2) + ")";
                        }
                    }
                } else {
                    failed_routes <- failed_routes + 1;
                }
            }
        }
        
        float success_rate <- nb > 0 ? (100.0 * successful_routes / nb) : 0.0;
        write "Taux de succes : " + (success_rate with_precision 1) + "%";
        
        if success_rate < 50 {
            write "ALERTE: Reseau tres peu connexe";
        } else if success_rate < 80 {
            write "ATTENTION: Reseau partiellement deconnecte";
        } else {
            write "OK: Reseau bien connecte";
        }
    }
    
    // EXPORT DU GRAPHE
    action export_graph_files {
        write "\n=== EXPORT GRAPHE ===";
        
        // Créer agents EDGE
        loop eid from: 0 to: length(edges_list) - 1 {
            list<int> e <- edges_list[eid];
            point p1 <- G_NODES[e[0]];
            point p2 <- G_NODES[e[1]];
            
            create edge_feature {
                edge_id <- eid;
                from_id <- e[0];
                to_id <- e[1];
                length_m <- EDGE_LENGTHS[eid];
                nb_routes <- length(EDGE_TO_ROUTES[eid]);
                shape <- line([p1, p2]);
            }
        }
        
        // Créer agents NODE
        loop nid over: G_NODES.keys {
            create node_feature {
                node_id <- nid;
                degree <- nid in G_ADJ.keys ? length(G_ADJ[nid]) : 0;
                shape <- G_NODES[nid];
            }
        }
        
        // Sauver shapefiles
        save edge_feature to: results_folder + "graph_edges.shp" format: "shp" 
            attributes: ["edge_id"::edge_id, "from_id"::from_id, "to_id"::to_id, 
                        "length_m"::length_m, "nb_routes"::nb_routes];
        
        save node_feature to: results_folder + "graph_nodes.shp" format: "shp" 
            attributes: ["node_id"::node_id, "degree"::degree];
        
        write "graph_edges.shp : " + length(edge_feature) + " aretes";
        write "graph_nodes.shp : " + length(node_feature) + " noeuds";
        
        // Nettoyer
        ask edge_feature { do die; }
        ask node_feature { do die; }
    }
    
    // RECHARGEMENT
    action load_graph_from_edges {
        write "\n=== RECHARGEMENT GRAPHE ===";
        
        node_ids <- []; 
        G_NODES <- []; 
        G_ADJ <- []; 
        edges_list <- [];
        EDGE_KEY_TO_ID <- [];
        node_counter <- 0;
        
        file edges_shp <- shape_file(results_folder + "graph_edges.shp");
        create edge_feature from: edges_shp with: [
            edge_id :: int(read("edge_id")),
            from_id :: int(read("from_id")),
            to_id :: int(read("to_id")),
            length_m :: float(read("length_m"))
        ];
        
        loop e over: edge_feature {
            list<point> pts <- e.shape.points;
            point p1 <- pts[0];
            point p2 <- pts[length(pts) - 1];
            
            int id1 <- get_or_create_node(p1);
            int id2 <- get_or_create_node(p2);
            
            int a <- min(id1, id2);
            int b <- max(id1, id2);
            list<int> ekey <- [a, b];
            
            if not (ekey in EDGE_KEY_TO_ID.keys) {
                int eid <- length(edges_list);
                edges_list << ekey;
                EDGE_KEY_TO_ID[ekey] <- eid;
                EDGE_LENGTHS << (p1 distance_to p2);
                
                if not (b in G_ADJ[a]) { G_ADJ[a] << b; }
                if not (a in G_ADJ[b]) { G_ADJ[b] << a; }
            }
        }
        
        write "Aretes rechargees : " + length(edges_list);
        write "Noeuds recharges : " + length(G_NODES);
        
        // Recréer graphe
        if length(edges_list) > 0 {
            list<geometry> graph_geoms <- [];
            loop e over: edges_list {
                graph_geoms << line([G_NODES[e[0]], G_NODES[e[1]]]);
            }
            road_graph <- as_edge_graph(graph_geoms);
        }
        
        ask edge_feature { do die; }
    }
    
    // FONCTIONS UTILITAIRES
    
    point snap_point(point p) {
        float x <- round(p.x / SNAP_TOL) * SNAP_TOL;
        float y <- round(p.y / SNAP_TOL) * SNAP_TOL;
        return {x, y, p.z};
    }
    
    int get_or_create_node(point p) {
        if not (p in node_ids.keys) {
            node_ids[p] <- node_counter;
            G_NODES[node_counter] <- p;
            G_ADJ[node_counter] <- [];
            node_counter <- node_counter + 1;
        }
        return node_ids[p];
    }
    
    action load_bus_network_robust {
        write "\n=== CHARGEMENT RESEAU BUS ===";
        
        int bus_parts_loaded <- 0;
        int bus_routes_count <- 0;
        int i <- 0;
        bool continue_loading <- true;
        
        loop while: continue_loading and i < 30 {
            string filename <- results_folder + "bus_routes_part" + i + ".shp";
            
            try {
                file shape_file_bus <- shape_file(filename);
                
                create bus_route from: shape_file_bus with: [
                    route_name::string(read("name")),
                    osm_id::string(read("osm_id")),
                    length_meters::float(read("length_m"))
                ];
                
                int routes_in_file <- length(shape_file_bus);
                bus_routes_count <- bus_routes_count + routes_in_file;
                bus_parts_loaded <- bus_parts_loaded + 1;
                
                write "  Part " + i + " : " + routes_in_file + " routes";
                i <- i + 1;
                
            } catch {
                write "  Fin detection a part " + i;
                continue_loading <- false;
            }
        }
        
        write "TOTAL : " + bus_routes_count + " routes en " + bus_parts_loaded + " fichiers";
    }
    
    action validate_world_envelope {
        write "\n=== VALIDATION ENVELOPPE ===";
        
        if shape != nil {
            write "Enveloppe definie : " + int(shape.width) + " x " + int(shape.height);
        } else {
            write "Creation enveloppe depuis donnees...";
            do create_envelope_from_data;
        }
    }
    
    action create_envelope_from_data {
        list<geometry> all_shapes <- [];
        
        loop route over: bus_route {
            if route.shape != nil {
                all_shapes <+ route.shape;
            }
        }
        
        if !empty(all_shapes) {
            geometry union_geom <- union(all_shapes);
            shape <- envelope(union_geom);
            write "Enveloppe creee : " + int(shape.width) + " x " + int(shape.height);
        } else {
            write "ERREUR: Impossible de creer enveloppe";
            shape <- rectangle(100000, 100000) at_location {587500, -2320000};
            write "Utilisation enveloppe par defaut";
        }
    }
}

species bus_route {
    string route_name;
    string osm_id;
    float length_meters;
    
    aspect default {
        if shape != nil {
            draw shape color: #lightblue width: 1.0;
        }
    }
}

species edge_feature {
    int edge_id;
    int from_id;
    int to_id;
    float length_m;
    int nb_routes;
    
    aspect default {
        draw shape color: #darkgreen width: 1.5;
    }
}

species node_feature {
    int node_id;
    int degree;
    
    aspect default {
        rgb node_color <- degree <= 1 ? #orange : #green;
        draw circle(5) color: node_color border: #black;
    }
}

species graph_issue {
    string issue_type;
    
    aspect default {
        if issue_type = "isolated" {
            draw circle(15) color: #red;
            draw "!" size: 8 color: #white;
        }
    }
}

experiment view_network type: gui {
    output {
        display "Reseau + Connectivite" background: #white type: 2d {
            graphics "graph_final" {
                loop edge over: edges_list {
                    point p1 <- G_NODES[edge[0]];
                    point p2 <- G_NODES[edge[1]];
                    
                    int eid <- EDGE_KEY_TO_ID[edge];
                    int nb <- eid in EDGE_TO_ROUTES.keys ? length(EDGE_TO_ROUTES[eid]) : 1;
                    rgb edge_color <- nb > 5 ? #darkgreen : (nb > 2 ? #green : #lightgreen);
                    
                    draw line([p1, p2]) color: edge_color width: 1.5;
                }
                
                loop node_id over: G_NODES.keys {
                    point p <- G_NODES[node_id];
                    int degree <- node_id in G_ADJ.keys ? length(G_ADJ[node_id]) : 0;
                    rgb node_color <- degree <= 1 ? #orange : #green;
                    draw circle(5) at: p color: node_color border: #black;
                }
            }
            
            species graph_issue;
            
            graphics "test_paths" {
                loop path_geom over: test_paths {
                    draw path_geom color: #blue width: 3.0;
                }
            }
            
            overlay position: {10, 10} size: {280 #px, 200 #px} background: #white transparency: 0.9 border: #black {
                draw "RESEAU BUS COMPLET" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                
                draw "GRAPHE" at: {15#px, 45#px} color: #black font: font("Arial", 10, #bold);
                draw "Noeuds: " + length(G_NODES) at: {20#px, 60#px} color: #darkgreen;
                draw "Aretes: " + length(edges_list) at: {20#px, 75#px} color: #darkgreen;
                
                draw "CONNECTIVITE" at: {15#px, 100#px} color: #black font: font("Arial", 10, #bold);
                draw "Composantes: " + nb_components at: {20#px, 115#px} 
                     color: (nb_components > 1 ? #red : #green);
                draw "Dead-ends: " + nb_dead_ends at: {20#px, 130#px} 
                     color: (nb_dead_ends > 50 ? #orange : #green);
                draw "Degre moy: " + (avg_degree with_precision 2) at: {20#px, 145#px}
                     color: (avg_degree > 1.5 ? #green : #red);
                
                draw "ROUTAGE" at: {15#px, 170#px} color: #black font: font("Arial", 10, #bold);
                int total_tests <- successful_routes + failed_routes;
                float success_rate <- total_tests > 0 ? (100.0 * successful_routes / total_tests) : 0.0;
                draw "Succes: " + (success_rate with_precision 1) + "%" at: {20#px, 185#px}
                     color: (success_rate > 80 ? #green : (success_rate > 50 ? #orange : #red));
            }
        }
    }
}