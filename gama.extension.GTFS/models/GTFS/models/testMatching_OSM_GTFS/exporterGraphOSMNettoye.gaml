/**
 * Name: Network_Bus_Clean_Export
 * Description: Construction du graphe bus + Export avec mapping route↔edge
 * Tags: shapefile, network, bus, graph, export
 * Date: 2025-10-01
 */

model Network_Bus_Clean_Export

global {
    // --- CONFIGURATION FICHIERS ---
    string results_folder <- "../../results/";
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // --- CONFIGURATION GRAPHE ---
    float SNAP_TOL <- 6.0;  // Tolérance de snap en mètres
    graph road_graph;
    map<point, int> node_ids <- [];  // point snappé -> id
    map<int, point> G_NODES <- [];   // id -> coord
    map<int, list<int>> G_ADJ <- []; // id -> voisins
    list<list<int>> edges_list <- []; // liste des arêtes [min_id, max_id]
    int node_counter <- 0;
    
    // --- MAPPING EDGES ↔ ROUTES ---
    map<list<int>, int> EDGE_KEY_TO_ID <- [];    // clé arête [a,b] -> edge_id
    map<int, list<string>> EDGE_TO_ROUTES <- []; // edge_id -> liste osm_id
    map<string, list<int>> ROUTE_TO_EDGES <- []; // osm_id -> liste edge_id
    list<float> EDGE_LENGTHS <- [];              // edge_id -> longueur (m)
    
    // --- MODE DE FONCTIONNEMENT ---
    bool rebuild_from_osm <- true;  // true = construire depuis OSM, false = recharger depuis export

    init {
        write "=== RÉSEAU BUS AVEC EXPORT ===";
        
        if rebuild_from_osm {
            // MODE 1 : Construction depuis OSM
            do load_bus_network_robust;
            do validate_world_envelope;
            do build_routable_graph;
            do export_graph_files;
        } else {
            // MODE 2 : Rechargement depuis export
            do validate_world_envelope;
            do load_graph_from_edges;
        }
        
        // Résumé
        write "\n=== RÉSUMÉ ===";
        write "Nœuds graphe : " + length(G_NODES);
        write "Arêtes graphe : " + length(edges_list);
        write "Graphe créé : " + (road_graph != nil ? "✅" : "❌");
        write "Relations edge→route : " + length(EDGE_TO_ROUTES);
    }
    
    // 🔧 CONSTRUCTION DU GRAPHE AVEC MAPPING
    action build_routable_graph {
        write "\n🔧 === CONSTRUCTION GRAPHE + MAPPING ===";
        
        int processed_routes <- 0;
        int valid_segments <- 0;
        
        // Parcourir chaque bus_route
        loop route over: bus_route {
            if route.shape != nil and route.shape.points != nil {
                list<point> points <- route.shape.points;
                
                if length(points) > 1 {
                    processed_routes <- processed_routes + 1;
                    string rid <- route.osm_id; // identifiant de la route
                    
                    // Traiter chaque segment de la polyligne
                    loop i from: 0 to: length(points) - 2 {
                        point p1 <- snap_point(points[i]);
                        point p2 <- snap_point(points[i + 1]);
                        
                        if p1 != p2 {
                            int id1 <- get_or_create_node(p1);
                            int id2 <- get_or_create_node(p2);
                            
                            // Clé non orientée pour dédoublonner
                            int a <- min(id1, id2);
                            int b <- max(id1, id2);
                            list<int> ekey <- [a, b];
                            
                            int eid;
                            
                            // Si l'arête existe déjà, on récupère son id
                            if (ekey in EDGE_KEY_TO_ID.keys) {
                                eid <- EDGE_KEY_TO_ID[ekey];
                            } else {
                                // Nouvelle arête
                                eid <- length(edges_list);
                                edges_list << ekey;
                                EDGE_KEY_TO_ID[ekey] <- eid;
                                
                                // Longueur (m)
                                float len <- G_NODES[a] distance_to G_NODES[b];
                                EDGE_LENGTHS << len;
                                
                                // Adjacence (une seule fois)
                                if not (b in G_ADJ[a]) { G_ADJ[a] << b; }
                                if not (a in G_ADJ[b]) { G_ADJ[b] << a; }
                                
                                valid_segments <- valid_segments + 1;
                            }
                            
                            // --- MAPPING vers la route courante ---
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
        
        write "✅ Routes traitées : " + processed_routes;
        write "✅ Arêtes uniques : " + valid_segments;
        write "✅ Nœuds créés : " + length(G_NODES);
        write "✅ Mappings edge→route : " + length(EDGE_TO_ROUTES);
    }
    
    // 📤 EXPORT DU GRAPHE + JOINTURE
    action export_graph_files {
        write "\n📤 === EXPORT GRAPHE ===";
        
        // 1) Créer les agents EDGE à partir des arêtes
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
        
        // 2) Créer les agents NODE à partir des nœuds
        loop nid over: G_NODES.keys {
            create node_feature {
                node_id <- nid;
                degree <- nid in G_ADJ.keys ? length(G_ADJ[nid]) : 0;
                shape <- G_NODES[nid];
            }
        }
        
        // 3) Sauver en shapefiles avec attributs
        save edge_feature to: results_folder + "graph_edges.shp" format: "shp" 
            attributes: ["edge_id"::edge_id, "from_id"::from_id, "to_id"::to_id, "length_m"::length_m, "nb_routes"::nb_routes];
        
        save node_feature to: results_folder + "graph_nodes.shp" format: "shp" 
            attributes: ["node_id"::node_id, "degree"::degree];
        
        write "✅ graph_edges.shp : " + length(edge_feature) + " arêtes";
        write "✅ graph_nodes.shp : " + length(node_feature) + " nœuds";
        
        // 4) Exporter la jointure edge ↔ route (CSV)
        save "edge_id,route_osm_id" to: results_folder + "edge_route.csv" format: "text" rewrite: true;
        
        loop eid over: EDGE_TO_ROUTES.keys {
            loop rid over: EDGE_TO_ROUTES[eid] {
                save (string(eid) + "," + rid) to: results_folder + "edge_route.csv" format: "text" rewrite: false;
            }
        }
        
        write "✅ edge_route.csv : " + sum(EDGE_TO_ROUTES.values collect length(each)) + " relations";
        
        // Nettoyer les agents techniques
        ask edge_feature { do die; }
        ask node_feature { do die; }
    }
    
    // 📥 RECHARGEMENT DEPUIS EXPORT
    action load_graph_from_edges {
        write "\n📥 === RECHARGEMENT GRAPHE ===";
        
        // Reset structures
        node_ids <- []; 
        G_NODES <- []; 
        G_ADJ <- []; 
        edges_list <- [];
        EDGE_KEY_TO_ID <- []; 
        EDGE_TO_ROUTES <- []; 
        ROUTE_TO_EDGES <- []; 
        EDGE_LENGTHS <- [];
        node_counter <- 0;
        
        // Recharger les arêtes
        file edges_shp <- shape_file(results_folder + "graph_edges.shp");
        create edge_feature from: edges_shp with: [
            edge_id :: int(read("edge_id")),
            from_id :: int(read("from_id")),
            to_id :: int(read("to_id")),
            length_m :: float(read("length_m"))
        ];
        
        // Reconstruire les structures depuis les lignes
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
        
        write "✅ Arêtes rechargées : " + length(edges_list);
        write "✅ Nœuds rechargés : " + length(G_NODES);
        
        // Reconstituer le mapping depuis CSV
        file map_csv <- file(results_folder + "edge_route.csv");
        list<string> lines <- map_csv.contents;
        
        // Sauter l'en-tête
        loop i from: 1 to: length(lines) - 1 {
            string line <- lines[i];
            list<string> cols <- line split_with ",";
            
            if length(cols) >= 2 {
                int eid <- int(cols[0]);
                string rid <- cols[1];
                
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
        
        write "✅ Mappings rechargés : " + length(EDGE_TO_ROUTES);
        
        // Recréer l'objet graph GAMA
        if length(edges_list) > 0 {
            list<geometry> graph_geoms <- [];
            loop e over: edges_list {
                graph_geoms << line([G_NODES[e[0]], G_NODES[e[1]]]);
            }
            road_graph <- as_edge_graph(graph_geoms);
        }
        
        // Nettoyer les agents techniques
        ask edge_feature { do die; }
    }
    
    // --- FONCTIONS UTILITAIRES ---
    
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
    
    // --- ACTIONS DE CHARGEMENT ---
    
    action load_bus_network_robust {
        write "\n🚌 === CHARGEMENT RÉSEAU BUS ===";
        
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
                
                write "  ✅ Part " + i + " : " + routes_in_file + " routes";
                i <- i + 1;
                
            } catch {
                write "  ℹ️ Fin détection à part " + i;
                continue_loading <- false;
            }
        }
        
        write "📊 TOTAL : " + bus_routes_count + " routes en " + bus_parts_loaded + " fichiers";
    }
    
    action validate_world_envelope {
        write "\n🌍 === VALIDATION ENVELOPPE ===";
        
        if shape != nil {
            write "✅ Enveloppe définie : " + int(shape.width) + " x " + int(shape.height);
        } else {
            write "⚠️ Création enveloppe depuis données...";
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
            write "✅ Enveloppe créée : " + int(shape.width) + " x " + int(shape.height);
        } else {
            write "❌ Impossible de créer enveloppe";
            shape <- rectangle(100000, 100000) at_location {587500, -2320000};
            write "⚠️ Utilisation enveloppe par défaut";
        }
    }
}

// AGENT ROUTE BUS
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

// AGENTS TECHNIQUES POUR EXPORT
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

// EXPÉRIMENT
experiment view_network type: gui {
    output {
        display "Réseau Final" background: #white type: 2d {
            // Graphe final
            graphics "graph_final" {
                // Arêtes
                loop edge over: edges_list {
                    point p1 <- G_NODES[edge[0]];
                    point p2 <- G_NODES[edge[1]];
                    
                    // Colorer selon nombre de routes utilisant cette arête
                    int eid <- EDGE_KEY_TO_ID[edge];
                    int nb <- eid in EDGE_TO_ROUTES.keys ? length(EDGE_TO_ROUTES[eid]) : 1;
                    rgb edge_color <- nb > 5 ? #darkgreen : (nb > 2 ? #green : #lightgreen);
                    
                    draw line([p1, p2]) color: edge_color width: 1.5;
                }
                
                // Nœuds
                loop node_id over: G_NODES.keys {
                    point p <- G_NODES[node_id];
                    int degree <- node_id in G_ADJ.keys ? length(G_ADJ[node_id]) : 0;
                    rgb node_color <- degree <= 1 ? #orange : #green;
                    draw circle(5) at: p color: node_color border: #black;
                }
            }
            
            // Overlay
            overlay position: {10, 10} size: {220 #px, 100 #px} background: #white transparency: 0.9 border: #black {
                draw "RÉSEAU BUS + EXPORT" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "Nœuds: " + length(G_NODES) at: {15#px, 40#px} color: #darkgreen;
                draw "Arêtes: " + length(edges_list) at: {15#px, 55#px} color: #darkgreen;
                draw "Mappings: " + length(EDGE_TO_ROUTES) at: {15#px, 70#px} color: #blue;
                draw "Snap: " + SNAP_TOL + "m" at: {15#px, 85#px} color: #gray size: 9;
            }
        }
    }
}