/*
 * TEST FONCTIONNALITÉ 3.12 - GRAPHES DE DÉPLACEMENT
 * ==================================================
 * Vérifie que la conversion polyligne → graphe fonctionne correctement
 * et que les bus peuvent naviguer sur les réseaux générés.
 *
 * CRITÈRES DE VALIDATION :
 * 1. Toutes les shapes peuvent être converties en graphes
 * 2. Les graphes sont navigables (nœuds connectés)
 * 3. La correspondance trip → shape → graphe fonctionne
 * 4. Un bus peut effectivement se déplacer sur le réseau
 */

model TestGraphesDeplacementComplet

global {
    // === CONFIGURATION ===
    string gtfs_dir <- "../../includes/tisseo_gtfs_v2";
    gtfs_file gtfs_f;
    
    // === STRUCTURES DE DONNÉES PRINCIPALES ===
    map<int, graph> shape_graphs <- []; // Graphes par shapeId
    map<string, int> trip_shape_map <- []; // Trip → Shape mapping
    
    // === MÉTRIQUES DE TEST ===
    int nb_shapes_total <- 0;
    int nb_graphes_crees <- 0;
    int nb_graphes_navigables <- 0;
    int nb_trips_avec_graphe <- 0;
    int nb_erreurs_critiques <- 0;
    
    // === RÉSULTATS DÉTAILLÉS ===
    list<int> shapes_problematiques <- [];
    list<int> graphes_non_navigables <- [];
    string selected_trip_id <- "2039311"; // Trip pour test pratique
    bool test_navigation_reussi <- false;
    
    // === SEUILS DE VALIDATION ===
    float seuil_reussite_graphes <- 0.95; // 95% des shapes doivent donner un graphe valide
    float seuil_navigabilite <- 0.90; // 90% des graphes doivent être navigables
    int min_aretes_pour_navigation <- 2; // Minimum d'arêtes pour être navigable

    init {
        write "🚀 === TEST FONCTIONNALITÉ 3.12 - GRAPHES DE DÉPLACEMENT ===";
        write "📋 Objectif : Valider la conversion polyligne → graphe → navigation";
        write "";
        
        // === ÉTAPE 1 : CHARGEMENT DES DONNÉES ===
        write "📂 Étape 1/5 : Chargement GTFS...";
        gtfs_f <- gtfs_file(gtfs_dir);
        if (gtfs_f = nil) {
            write "❌ ERREUR CRITIQUE : Impossible de charger le GTFS !";
            do die;
        }
        
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f;
        nb_shapes_total <- length(transport_shape);
        write "✅ " + string(nb_shapes_total) + " shapes chargées";
        write "✅ " + string(length(bus_stop)) + " arrêts chargés";
        write "";
        
        // === ÉTAPE 2 : GÉNÉRATION DES GRAPHES ===
        write "🔧 Étape 2/5 : Génération des graphes de déplacement...";
        loop s over: transport_shape {
            if (s.shape != nil and length(s.shape.points) > 1) {
                try {
                    // Méthode recommandée : segments explicites
                    list<geometry> segments <- [];
                    list<point> pts <- s.shape.points;
                    
                    loop i from: 0 to: length(pts) - 2 {
                        geometry seg <- line([pts[i], pts[i+1]]);
                        if (seg != nil and seg.perimeter > 0.1) {
                            segments <- segments + seg;
                        }
                    }
                    
                    if (length(segments) >= min_aretes_pour_navigation) {
                        graph g <- as_edge_graph(segments);
                        if (g != nil) {
                            shape_graphs[s.shapeId] <- g;
                            nb_graphes_crees <- nb_graphes_crees + 1;
                        } else {
                            shapes_problematiques <- shapes_problematiques + s.shapeId;
                            nb_erreurs_critiques <- nb_erreurs_critiques + 1;
                        }
                    } else {
                        write "⚠️ Shape " + string(s.shapeId) + " : pas assez de segments valides (" + string(length(segments)) + ")";
                        shapes_problematiques <- shapes_problematiques + s.shapeId;
                    }
                } catch {
                    write "❌ Erreur lors de la création du graphe pour shape " + string(s.shapeId);
                    shapes_problematiques <- shapes_problematiques + s.shapeId;
                    nb_erreurs_critiques <- nb_erreurs_critiques + 1;
                }
            } else {
                write "⚠️ Shape " + string(s.shapeId) + " ignorée (géométrie invalide)";
                shapes_problematiques <- shapes_problematiques + s.shapeId;
            }
        }
        
        float taux_creation <- nb_shapes_total > 0 ? (nb_graphes_crees / nb_shapes_total) : 0.0;
        write "✅ " + string(nb_graphes_crees) + "/" + string(nb_shapes_total) + " graphes créés (" + string(int(taux_creation * 100)) + "%)";
        write "";
        
        // === ÉTAPE 3 : TEST DE NAVIGABILITÉ ===
        write "🧭 Étape 3/5 : Test de navigabilité des graphes...";
        loop shape_id over: shape_graphs.keys {
            graph g <- shape_graphs[shape_id];
            
            if (g != nil) {
                // Test de connectivité
                int nb_vertices <- length(g.vertices);
                int nb_edges <- length(g.edges);
                
                if (nb_vertices >= 2 and nb_edges >= 1) {
                    // Test de chemin entre premier et dernier nœud
                    list vertices_list <- g.vertices;
                    if (vertices_list != nil and length(vertices_list) >= 2) {
                        try {
                            // Méthode alternative : utiliser les points de la polyligne originale
                            transport_shape current_shape <- first(transport_shape where (each.shapeId = shape_id));
                            if (current_shape != nil and current_shape.shape != nil and current_shape.shape.points != nil) {
                                list<point> shape_points <- current_shape.shape.points;
                                if (length(shape_points) >= 2) {
                                    point first_location <- shape_points[0];
                                    point last_location <- shape_points[length(shape_points) - 1];
                                    
                                    if (first_location != nil and last_location != nil) {
                                        path test_path <- path_between(g, first_location, last_location);
                                        if (test_path != nil and test_path.edges != nil and length(test_path.edges) > 0) {
                                            nb_graphes_navigables <- nb_graphes_navigables + 1;
                                        } else {
                                            graphes_non_navigables <- graphes_non_navigables + shape_id;
                                        }
                                    } else {
                                        write "⚠️ Shape " + string(shape_id) + " : points de polyligne nil";
                                        graphes_non_navigables <- graphes_non_navigables + shape_id;
                                    }
                                } else {
                                    write "⚠️ Shape " + string(shape_id) + " : pas assez de points dans la polyligne";
                                    graphes_non_navigables <- graphes_non_navigables + shape_id;
                                }
                            } else {
                                write "⚠️ Shape " + string(shape_id) + " : polyligne originale inaccessible";
                                graphes_non_navigables <- graphes_non_navigables + shape_id;
                            }
                        } catch {
                            write "❌ Erreur lors du test de navigabilité pour shape " + string(shape_id);
                            graphes_non_navigables <- graphes_non_navigables + shape_id;
                        }
                    } else {
                        graphes_non_navigables <- graphes_non_navigables + shape_id;
                    }
                } else {
                    graphes_non_navigables <- graphes_non_navigables + shape_id;
                }
            } else {
                write "⚠️ Graphe nil pour shape " + string(shape_id);
                graphes_non_navigables <- graphes_non_navigables + shape_id;
            }
        }
        
        float taux_navigabilite <- nb_graphes_crees > 0 ? (nb_graphes_navigables / nb_graphes_crees) : 0.0;
        write "✅ " + string(nb_graphes_navigables) + "/" + string(nb_graphes_crees) + " graphes navigables (" + string(int(taux_navigabilite * 100)) + "%)";
        write "";
        
        // === ÉTAPE 4 : CONSTRUCTION DU MAPPING TRIP → SHAPE ===
        write "🗺️ Étape 4/5 : Construction du mapping trip → shape → graphe...";
        ask bus_stop {
            if (tripShapeMap != nil) {
                loop trip_id over: tripShapeMap.keys {
                    int shape_id <- tripShapeMap[trip_id];
                    if (myself.shape_graphs contains_key shape_id) {
                        myself.trip_shape_map[trip_id] <- shape_id;
                        myself.nb_trips_avec_graphe <- myself.nb_trips_avec_graphe + 1;
                    }
                }
            }
        }
        
        write "✅ " + string(length(trip_shape_map)) + " trips uniques avec graphe disponible";
        write "✅ " + string(nb_trips_avec_graphe) + " associations trip → graphe créées";
        write "";
        
        write "📊 Tests de validation au prochain cycle...";
    }

    reflex test_validation when: cycle = 2 {
        write "🔍 === ÉTAPE 5/5 : VALIDATION COMPLÈTE ===";
        write "";
        
        // === TEST 1 : TAUX DE CRÉATION DE GRAPHES ===
        float taux_creation <- nb_shapes_total > 0 ? (nb_graphes_crees / nb_shapes_total) : 0.0;
        bool test1_ok <- taux_creation >= seuil_reussite_graphes;
        
        write "📊 TEST 1 - Taux de création de graphes :";
        write "   Résultat : " + string(int(taux_creation * 100)) + "% (seuil : " + string(int(seuil_reussite_graphes * 100)) + "%)";
        write "   Status : " + (test1_ok ? "✅ RÉUSSI" : "❌ ÉCHEC");
        write "";
        
        // === TEST 2 : NAVIGABILITÉ ===
        float taux_navigabilite <- nb_graphes_crees > 0 ? (nb_graphes_navigables / nb_graphes_crees) : 0.0;
        bool test2_ok <- taux_navigabilite >= seuil_navigabilite;
        
        write "🧭 TEST 2 - Navigabilité des graphes :";
        write "   Résultat : " + string(int(taux_navigabilite * 100)) + "% (seuil : " + string(int(seuil_navigabilite * 100)) + "%)";
        write "   Status : " + (test2_ok ? "✅ RÉUSSI" : "❌ ÉCHEC");
        write "";
        
        // === TEST 3 : MAPPING TRIP → GRAPHE ===
        bool test3_ok <- (selected_trip_id in trip_shape_map.keys);
        
        write "🗺️ TEST 3 - Mapping trip → shape → graphe :";
        if (test3_ok) {
            int shape_id <- trip_shape_map[selected_trip_id];
            write "   Trip '" + selected_trip_id + "' → Shape " + string(shape_id) + " ✅";
            write "   Graphe disponible : " + (shape_graphs contains_key shape_id ? "✅ OUI" : "❌ NON");
        } else {
            write "   Trip '" + selected_trip_id + "' : ❌ MAPPING MANQUANT";
        }
        write "   Status : " + (test3_ok ? "✅ RÉUSSI" : "❌ ÉCHEC");
        write "";
        
        // === TEST 4 : NAVIGATION PRATIQUE ===
        write "🚌 TEST 4 - Navigation pratique d'un bus :";
        if (test3_ok) {
            int shape_id <- trip_shape_map[selected_trip_id];
            graph test_network <- shape_graphs[shape_id];
            
            if (test_network != nil) {
                try {
                    // Utiliser les points de la polyligne originale pour plus de fiabilité
                    transport_shape current_shape <- first(transport_shape where (each.shapeId = shape_id));
                    if (current_shape != nil and current_shape.shape != nil and current_shape.shape.points != nil) {
                        list<point> shape_points <- current_shape.shape.points;
                        if (length(shape_points) >= 2) {
                            point start_pos <- shape_points[0];
                            point end_pos <- shape_points[length(shape_points) - 1];
                            
                            if (start_pos != nil and end_pos != nil) {
                                path test_path <- path_between(test_network, start_pos, end_pos);
                                if (test_path != nil and test_path.edges != nil and length(test_path.edges) > 0) {
                                    test_navigation_reussi <- true;
                                    write "   Navigation start → end : ✅ POSSIBLE";
                                    write "   Chemin : " + string(length(test_path.edges)) + " segments";
                                    write "   Distance : " + string(int(start_pos distance_to end_pos)) + " mètres";
                                    
                                    // Créer un bus test pour validation finale
                                    create bus_test with: [
                                        test_network:: test_network,
                                        start_location:: start_pos,
                                        target_location:: end_pos
                                    ];
                                    write "   Bus test créé : ✅ SUCCÈS";
                                } else {
                                    write "   Navigation : ❌ IMPOSSIBLE (pas de chemin calculé)";
                                    write "   Debug : test_path = " + (test_path = nil ? "nil" : "non-nil");
                                }
                            } else {
                                write "   Navigation : ❌ IMPOSSIBLE (points start/end nil)";
                            }
                        } else {
                            write "   Navigation : ❌ IMPOSSIBLE (pas assez de points dans shape)";
                        }
                    } else {
                        write "   Navigation : ❌ IMPOSSIBLE (shape originale inaccessible)";
                    }
                } catch {
                    write "   Navigation : ❌ ERREUR lors du test de navigation";
                }
            } else {
                write "   Navigation : ❌ IMPOSSIBLE (graphe nil)";
            }
        } else {
            write "   Navigation : ❌ IMPOSSIBLE (pas de mapping)";
        }
        write "   Status : " + (test_navigation_reussi ? "✅ RÉUSSI" : "❌ ÉCHEC");
        write "";
        
        // === BILAN FINAL ===
        write "📋 === BILAN FINAL DE LA FONCTIONNALITÉ 3.12 ===";
        write "";
        
        bool test_global_ok <- test1_ok and test2_ok and test3_ok and test_navigation_reussi;
        int nb_tests_reussis <- (test1_ok ? 1 : 0) + (test2_ok ? 1 : 0) + (test3_ok ? 1 : 0) + (test_navigation_reussi ? 1 : 0);
        
        write "🎯 RÉSULTATS GLOBAUX :";
        write "   Tests réussis : " + string(nb_tests_reussis) + "/4";
        write "   Erreurs critiques : " + string(nb_erreurs_critiques);
        write "   Shapes problématiques : " + string(length(shapes_problematiques));
        write "";
        
        if (test_global_ok) {
            write "🎉 FONCTIONNALITÉ 3.12 : ✅ VALIDÉE";
            write "✨ Les graphes de déplacement fonctionnent correctement";
            write "🚌 Les bus peuvent naviguer sur les réseaux GTFS";
        } else {
            write "🚨 FONCTIONNALITÉ 3.12 : ❌ NON VALIDÉE";
            write "";
            write "🔧 ACTIONS CORRECTIVES REQUISES :";
            if not test1_ok {
                write "   • Améliorer la création de graphes (actuellement " + string(int(taux_creation * 100)) + "%)";
            }
            if not test2_ok {
                write "   • Corriger la navigabilité (actuellement " + string(int(taux_navigabilite * 100)) + "%)";
            }
            if not test3_ok {
                write "   • Vérifier le mapping trip → shape pour '" + selected_trip_id + "'";
            }
            if not test_navigation_reussi {
                write "   • Résoudre les problèmes de navigation pratique";
            }
        }
        
        // === RECOMMANDATIONS ===
        if (length(shapes_problematiques) > 0 and length(shapes_problematiques) <= 10) {
            write "   • Vérifier manuellement les shapes : " + string(shapes_problematiques);
        } else if (length(shapes_problematiques) > 10) {
            write "   • " + string(length(shapes_problematiques)) + " shapes problématiques détectées";
        }
        if (nb_erreurs_critiques > 0) {
            write "   • " + string(nb_erreurs_critiques) + " erreurs critiques nécessitent une investigation";
        }
       
    }
}

// === SPECIES POUR LES AGENTS GTFS ===
species bus_stop skills: [TransportStopSkill] { }
species transport_shape skills: [TransportShapeSkill] { }

// === SPECIES POUR LE TEST DE NAVIGATION ===
species bus_test skills: [moving] {
    graph test_network;
    point start_location;
    point target_location;
    float speed <- 20.0 #km/#h;
    bool arrived <- false;
    
    init {
        location <- start_location;
    }
    
    reflex navigate when: not arrived and target_location != nil {
        if (location distance_to target_location > 10.0) {
            do goto target: target_location on: test_network speed: speed;
        } else {
            location <- target_location;
            arrived <- true;
            write "🎯 Bus test arrivé à destination - Navigation validée !";
        }
    }
    
    aspect base {
        draw circle(50) color: #orange border: #red;
    }
}

experiment TestGraphesDeplacementExperiment type: gui {
    parameter "Répertoire GTFS" var: gtfs_dir category: "Configuration";
    parameter "Trip ID de test" var: selected_trip_id category: "Test";
    parameter "Seuil réussite graphes (%)" var: seuil_reussite_graphes min: 0.5 max: 1.0 step: 0.05 category: "Validation";
    parameter "Seuil navigabilité (%)" var: seuil_navigabilite min: 0.5 max: 1.0 step: 0.05 category: "Validation";
    
    output {
        monitor "📊 Shapes totales" value: nb_shapes_total;
        monitor "🔧 Graphes créés" value: nb_graphes_crees;
        monitor "🧭 Graphes navigables" value: nb_graphes_navigables;
        monitor "🗺️ Trips avec graphe" value: length(trip_shape_map);
        monitor "❌ Erreurs critiques" value: nb_erreurs_critiques;
        monitor "🎯 Test navigation" value: test_navigation_reussi ? "✅ RÉUSSI" : "❌ ÉCHEC";
        
        display "Validation Graphes de Déplacement" {
            species bus_test aspect: base;
            
            graphics "Résultats" {
                draw "TEST FONCTIONNALITÉ 3.12 - GRAPHES DE DÉPLACEMENT" at: {10, 10} 
                     color: #black font: font("Arial", 14, #bold);
                
                float taux_global <- nb_shapes_total > 0 ? (nb_graphes_navigables / nb_shapes_total) : 0.0;
                rgb couleur <- taux_global >= 0.9 ? #green : (taux_global >= 0.7 ? #orange : #red);
                
                draw ("Taux de réussite global: " + string(int(taux_global * 100)) + "%") at: {10, 40} 
                     color: couleur font: font("Arial", 12, #bold);
                
                draw ("Graphes navigables: " + string(nb_graphes_navigables) + "/" + string(nb_graphes_crees)) at: {10, 70} 
                     color: #blue font: font("Arial", 11);
                
                draw ("Navigation test: " + (test_navigation_reussi ? "✅ VALIDÉE" : "❌ ÉCHEC")) at: {10, 100} 
                     color: test_navigation_reussi ? #green : #red font: font("Arial", 11, #bold);
            }
        }
    }
}