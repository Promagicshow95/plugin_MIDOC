/**
 * Name: Network_Bus_Only_Routable
 * Description: Test de routabilité du réseau bus depuis shapefiles OSM
 * Tags: shapefile, network, bus, routing, connectivity
 * Date: 2025-09-30
 */

model Network_Bus_Only_Routable

global {
    // --- CONFIGURATION FICHIERS ---
    string results_folder <- "../../results/";
    file data_file <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(data_file);
    
    // --- CONFIGURATION GRAPHE & ROUTING ---
    float SNAP_TOL <- 6.0;  // Tolérance de snap en mètres
    graph road_graph;
    map<point, int> node_ids <- [];  // point snappé -> id
    map<int, point> G_NODES <- [];   // id -> coord
    map<int, list<int>> G_ADJ <- []; // id -> voisins
    list<list<int>> edges_list <- [];
    int node_counter <- 0;
    
    // --- DIAGNOSTICS ---
    int nb_components <- 0;
    int nb_dead_ends <- 0; 
    float avg_degree <- 0.0;
    list<int> isolated_nodes <- [];
    list<geometry> test_paths <- [];
    int successful_routes <- 0;
    int failed_routes <- 0;
    
    // --- VARIABLES STATISTIQUES ---
    int total_bus_routes <- 0;
    
    // --- PARAMÈTRES D'AFFICHAGE ---
    bool show_bus <- true;
    bool show_graph_issues <- true;
    bool show_test_paths <- true;

    init {
        write "=== CHARGEMENT RÉSEAU BUS ROUTABLE ===";
        
        //  CHARGEMENT RÉSEAU BUS
        do load_bus_network_robust;
        
        //  VALIDER L'ENVELOPPE DU MONDE
        do validate_world_envelope;
        
        //  CONSTRUCTION GRAPHE ROUTABLE
        do build_routable_graph;
        
        //  TESTS DE CONNECTIVITÉ
        do check_connectivity;
        
        //  TESTS DE ROUTAGE
        do random_routing_tests(30);
        
        // Statistiques finales
        write "\n=== RÉSUMÉ FINAL ===";
        write " Routes Bus : " + total_bus_routes;
        write " Nœuds graphe : " + length(G_NODES);
        write " Arêtes graphe : " + length(edges_list);
        write " Composantes connexes : " + nb_components;
        write " Dead-ends : " + nb_dead_ends;
        write " Degré moyen : " + (avg_degree with_precision 2);
        write " Routages réussis : " + successful_routes + "/" + (successful_routes + failed_routes);
    }
    
    // 🔧 CONSTRUCTION DU GRAPHE ROUTABLE
    action build_routable_graph {
        write "\n🔧 === CONSTRUCTION GRAPHE ROUTABLE ===";
        
        int processed_routes <- 0;
        int valid_segments <- 0;
        
        // Parcourir chaque bus_route
        loop route over: bus_route {
            if route.shape != nil and route.shape.points != nil {
                list<point> points <- route.shape.points;
                
                if length(points) > 1 {
                    processed_routes <- processed_routes + 1;
                    
                    // Traiter chaque segment de la polyligne
                    loop i from: 0 to: length(points) - 2 {
                        point p1 <- snap_point(points[i]);
                        point p2 <- snap_point(points[i + 1]);
                        
                        // Ne pas créer d'arête entre points identiques après snap
                        if p1 != p2 {
                            // Obtenir ou créer les IDs des nœuds
                            int id1 <- get_or_create_node(p1);
                            int id2 <- get_or_create_node(p2);
                            
                            // Ajouter l'arête si elle n'existe pas
                            if not edge_exists(id1, id2) {
                                list<int> edge <- [id1, id2];
                                edges_list << edge;
                                do add_edge_to_adjacency(edge);
                                valid_segments <- valid_segments + 1;
                            }
                        }
                    }
                }
            }
        }
        
        // Créer le graphe GAMA
        if length(G_NODES) > 0 {
            // Créer une liste de lignes pour le graphe
            list<geometry> graph_edges <- [];
            
            loop edge over: edges_list {
                point p1 <- G_NODES[edge[0]];
                point p2 <- G_NODES[edge[1]];
                geometry line_edge <- line([p1, p2]);
                graph_edges << line_edge;
            }
            
            // Créer le graphe à partir des arêtes
            if length(graph_edges) > 0 {
                road_graph <- as_edge_graph(graph_edges);
            }
        }
        
        write "✅ Routes traitées : " + processed_routes + "/" + length(bus_route);
        write "✅ Segments valides : " + valid_segments;
        write "✅ Nœuds créés : " + length(G_NODES);
        write "✅ Arêtes créées : " + length(edges_list);
    }
    
    //  CHECK CONNECTIVITÉ
    action check_connectivity {
        write "\n === ANALYSE CONNECTIVITÉ ===";
        
        if length(G_NODES) = 0 {
            write "❌ Pas de nœuds dans le graphe!";
        } else {
            // Analyse des composantes connexes via BFS
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
            
            // Identifier les petites composantes (isolées)
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
            
            // Créer agents pour visualisation des problèmes
            loop node_id over: isolated_nodes {
                point node_location <- G_NODES[node_id];
                create graph_issue {
                    location <- node_location;
                    issue_type <- "isolated";
                }
            }
            
            write "🌐 Composantes connexes : " + nb_components;
            write "🔴 Nœuds isolés : " + length(isolated_nodes);
            write "🚦 Dead-ends : " + nb_dead_ends;
            write "📊 Degré moyen : " + (avg_degree with_precision 2);
            
            // Trouver la plus grande composante
            if not empty(components) {
                int max_size <- max(components collect length(each));
                write "🌟 Plus grande composante : " + max_size + " nœuds (" + 
                      ((100.0 * max_size / length(G_NODES)) with_precision 1) + "%)";
            }
        }
    }
    
    // TESTS DE ROUTAGE ALÉATOIRES
    action random_routing_tests(int nb) {
        write "\n🚗 === TESTS DE ROUTAGE ===";
        
        if road_graph = nil or length(G_NODES) < 2 {
            write "❌ Graphe insuffisant pour tests de routage";
        } else {
            list<point> nodes_list <- G_NODES.values;
            
            loop i from: 0 to: nb - 1 {
                point source <- one_of(nodes_list);
                point target <- one_of(nodes_list);
                
                if source != target {
                    path test_path <- path_between(road_graph, source, target);
                    
                    if test_path != nil {
                        successful_routes <- successful_routes + 1;
                        
                        // Garder quelques chemins pour visualisation
                        if length(test_paths) < 5 {
                            test_paths << test_path.shape;
                            
                            // Calculer ratio chemin/Euclidien
                            float path_length <- test_path.shape.perimeter;
                            float euclidean <- source distance_to target;
                            float ratio <- euclidean > 0 ? path_length / euclidean : 0.0;
                            
                            if ratio > 3.0 {
                                write "⚠️ Chemin très indirect : ratio " + (ratio with_precision 2);
                            }
                        }
                    } else {
                        failed_routes <- failed_routes + 1;
                    }
                }
            }
            
            float success_rate <- nb > 0 ? (100.0 * successful_routes / nb) : 0.0;
            write "✅ Taux de succès : " + (success_rate with_precision 1) + "%";
            
            if success_rate < 50 {
                write "⚠️ ATTENTION : Réseau peu connexe!";
            } else if success_rate < 80 {
                write "⚠️ Réseau partiellement déconnecté";
            } else {
                write "✅ Réseau bien connecté";
            }
        }
    }
    
    // --- FONCTIONS UTILITAIRES ---
    
    // Snapper un point sur la grille de tolérance
    point snap_point(point p) {
        float x <- round(p.x / SNAP_TOL) * SNAP_TOL;
        float y <- round(p.y / SNAP_TOL) * SNAP_TOL;
        point result <- {x, y, p.z};
        return result;
    }
    
    // Obtenir ou créer un ID de nœud
    int get_or_create_node(point p) {
        if not (p in node_ids.keys) {
            node_ids[p] <- node_counter;
            G_NODES[node_counter] <- p;
            G_ADJ[node_counter] <- [];
            node_counter <- node_counter + 1;
        }
        int result <- node_ids[p];
        return result;
    }
    
    // Vérifier si une arête existe
    bool edge_exists(int id1, int id2) {
        bool result <- false;
        if id1 in G_ADJ.keys {
            result <- id2 in G_ADJ[id1];
        }
        return result;
    }
    
    // Ajouter à la liste d'adjacence
    action add_edge_to_adjacency(list<int> edge) {
        int id1 <- edge[0];
        int id2 <- edge[1];
        if not (id2 in G_ADJ[id1]) {
            G_ADJ[id1] << id2;
        }
        if not (id1 in G_ADJ[id2]) {
            G_ADJ[id2] << id1;
        }
    }
    
    // === ACTIONS ORIGINALES DU MODÈLE (conservées) ===
    
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
                    osm_uid::string(read("osm_uid")),
                    osm_type::string(read("osm_type")),
                    route_type::string(read("route_type")),
                    highway_type::string(read("highway")),
                    length_meters::float(read("length_m"))
                ];
                
                int routes_in_file <- length(shape_file_bus);
                bus_routes_count <- bus_routes_count + routes_in_file;
                bus_parts_loaded <- bus_parts_loaded + 1;
                
                write "  ✅ Part " + i + " : " + routes_in_file + " routes";
                i <- i + 1;
                
            } catch {
                write "  ℹ️ Fin détection à part" + i;
                continue_loading <- false;
            }
        }
        
        total_bus_routes <- bus_routes_count;
        write "📊 TOTAL BUS : " + bus_routes_count + " routes en " + bus_parts_loaded + " fichiers";
    }
    
    action validate_world_envelope {
        write "\n🌍 === VALIDATION ENVELOPPE ===";
        
        if shape != nil {
            write "✅ Enveloppe définie : " + int(shape.width) + " x " + int(shape.height);
        } else {
            write "❌ Pas d'enveloppe définie";
            do create_envelope_from_data;
        }
    }
    
    action create_envelope_from_data {
        write "🔧 Création enveloppe depuis données bus...";
        
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

// AGENT ROUTE BUS (original)
species bus_route {
    string route_name;
    string osm_id;
    string osm_uid;
    string osm_type;
    string route_type;
    string highway_type;
    float length_meters;
    
    aspect default {
        if shape != nil {
            draw shape color: #blue width: 2.0;
        }
    }
    
    aspect routable {
        if shape != nil {
            draw shape color: #navy width: 1.5;
        }
    }
}

// AGENT POUR PROBLÈMES DE GRAPHE
species graph_issue {
    string issue_type;
    
    aspect default {
        if issue_type = "isolated" {
            draw circle(15) color: #red;
            draw "!" size: 8 color: #white;
        }
    }
}

//  EXPÉRIMENT ROUTABILITÉ
experiment test_routability type: gui {
    output {
        display "Réseau Routable" background: #white type: 2d {
            species bus_route aspect: routable;
            
            // Afficher les problèmes de connectivité
            species graph_issue;
            
            // Afficher les chemins de test
            graphics "test_paths" {
                loop path_geom over: test_paths {
                    draw path_geom color: #green width: 3.0;
                }
            }
            
            overlay position: {10, 10} size: {340 #px, 280 #px} background: #white transparency: 0.9 border: #black {
                draw "=== TEST ROUTABILITÉ ===" at: {10#px, 20#px} color: #black font: font("Arial", 13, #bold);
                
                // Stats réseau
                draw " RÉSEAU" at: {20#px, 45#px} color: #darkblue font: font("Arial", 11, #bold);
                draw " Routes : " + length(bus_route) at: {30#px, 65#px} color: #blue;
                draw " Nœuds : " + length(G_NODES) at: {30#px, 80#px} color: #blue;
                draw " Arêtes : " + length(edges_list) at: {30#px, 95#px} color: #blue;
                
                // Stats connectivité
                draw " CONNECTIVITÉ" at: {20#px, 120#px} color: #darkblue font: font("Arial", 11, #bold);
                draw "Composantes : " + nb_components at: {30#px, 140#px} color: (nb_components > 1 ? #orange : #green);
                draw "Dead-ends : " + nb_dead_ends at: {30#px, 155#px} color: (nb_dead_ends > 10 ? #orange : #green);
                draw "Degré moy : " + (avg_degree with_precision 2) at: {30#px, 170#px} color: (avg_degree > 1.5 ? #green : #red);
                
                // Stats routage
                draw " ROUTAGE" at: {20#px, 195#px} color: #darkblue font: font("Arial", 11, #bold);
                int total_tests <- successful_routes + failed_routes;
                float success_rate <- total_tests > 0 ? (100.0 * successful_routes / total_tests) : 0.0;
                rgb route_color <- success_rate > 80 ? #green : (success_rate > 50 ? #orange : #red);
                draw "Tests OK : " + successful_routes + "/" + total_tests at: {30#px, 215#px} color: route_color;
                draw "Taux : " + (success_rate with_precision 1) + "%" at: {30#px, 230#px} color: route_color;
                
                // Légende
                draw " Points isolés | 🟢 Chemins tests" at: {20#px, 255#px} color: #gray size: 9;
            }
        }
        
        // Vue détaillée du graphe
        display "Graphe Détaillé" background: #lightgray type: 2d {
            species bus_route aspect: routable transparency: 0.3;
            
            // Afficher les nœuds du graphe
            graphics "graph_nodes" {
                loop node_id over: G_NODES.keys {
                    point p <- G_NODES[node_id];
                    int degree <- node_id in G_ADJ.keys ? length(G_ADJ[node_id]) : 0;
                    
                    rgb node_color <- degree = 0 ? #red : (degree = 1 ? #orange : (degree = 2 ? #yellow : #green));
                    draw circle(8) at: p color: node_color;
                }
            }
            
            // Afficher les arêtes du graphe
            graphics "graph_edges" {
                loop edge over: edges_list {
                    point p1 <- G_NODES[edge[0]];
                    point p2 <- G_NODES[edge[1]];
                    draw line([p1, p2]) color: #darkgreen width: 0.5;
                }
            }
            
            overlay position: {10, 10} size: {200 #px, 100 #px} background: #white transparency: 0.9 border: #black {
                draw "GRAPHE DÉTAILLÉ" at: {10#px, 20#px} color: #black font: font("Arial", 11, #bold);
                draw " Isolé 🟠 Dead-end" at: {20#px, 40#px} color: #gray size: 9;
                draw " Degré 2 🟢 Connexion" at: {20#px, 55#px} color: #gray size: 9;
                draw "Snap: " + SNAP_TOL + "m" at: {20#px, 75#px} color: #darkblue size: 9;
            }
        }
    }
}