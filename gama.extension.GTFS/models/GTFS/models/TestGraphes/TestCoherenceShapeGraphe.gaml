model TestCoherenceShapeGrapheSegments

global {
    string gtfs_dir <- "../../includes/tisseo_gtfs_v2";
    gtfs_file gtfs_f;
    map<int, graph> shape_graphs <- [];
    int errors_total <- 0;
    int nb_shapes_tested <- 0;
    int nb_shapes_total <- 0;

    init {
        write "🚍 Test cohérence Shape-Graphe - Chargement GTFS...";
        gtfs_f <- gtfs_file(gtfs_dir);
        if (gtfs_f = nil) {
            write "❌ Erreur : impossible de charger le GTFS.";
            do die;
        }
        create transport_shape from: gtfs_f;
        nb_shapes_total <- length(transport_shape);
        write "📊 " + string(nb_shapes_total) + " shapes chargées.";

        // Génération des graphes à partir de segments individuels (méthode fiable)
        loop s over: transport_shape {
            if (s.shape != nil and length(s.shape.points) > 1) {
                list<geometry> segments <- [];
                loop i from: 0 to: length(s.shape.points) - 2 {
                    segments <- segments + line([s.shape.points[i], s.shape.points[i+1]]);
                }
                shape_graphs[s.shapeId] <- as_edge_graph(segments);
            } else {
                write "⚠️ Shape " + string(s.shapeId) + " ignorée (géométrie invalide)";
            }
        }
        write "✅ Génération des graphes terminée. Test au prochain cycle...";
    }

    reflex test_polyligne_graphe when: cycle = 2 {
        write "🔍 Début du test de cohérence polyligne-graphe";
        errors_total <- 0;
        nb_shapes_tested <- 0;

        // Filtrer les shapes valides
        list<transport_shape> shapes_valides <- transport_shape where (each.shape != nil and length(each.shape.points) > 1);

        // On teste sur un échantillon (ex : 5 shapes, modifiable)
        int nb_test <- min(5, length(shapes_valides));
        list<transport_shape> shapes_test <- first(shapes_valides, nb_test);

        write "📋 Test sur " + string(nb_test) + " shapes (sur " + string(length(shapes_valides)) + " valides)";
        write "──────────────────────────────────────────────";
        
        loop s over: shapes_test {
            nb_shapes_tested <- nb_shapes_tested + 1;
            int nb_points <- length(s.shape.points);
            // Nouveau : compter les points uniques
            int nb_points_uniques <- length(remove_duplicates(s.shape.points));
            int nb_segments_attendus <- nb_points - 1;

            // Récupération du graphe généré
            graph g <- shape_graphs[s.shapeId];

            int nodes <- (g != nil) ? length(g.vertices) : -1;
            int edges <- (g != nil) ? length(g.edges) : -1;

            // Affichage pour traçabilité
            write "shapeId=" + string(s.shapeId) + " | points: " + string(nb_points) +
                  " | uniques: " + string(nb_points_uniques);
            write "  🎯 SEGMENTS: " + string(nodes) + " nœuds / " + string(edges) + " arêtes";
            write "  - Attendu:  " + string(nb_points_uniques) + " nœuds / " + string(nb_segments_attendus) + " arêtes";
            
            if (nb_points != nb_points_uniques) {
                write "  ℹ️  Note : " + string(nb_points - nb_points_uniques) + " point(s) dupliqué(s) dans la polyligne (non compté comme erreur)";
            }

            bool coherent <- (nodes = nb_points_uniques and edges = nb_segments_attendus);

            if (coherent) {
                write "  ✅ Cohérence OK";
            } else {
                write "  ❌ Incohérence détectée";
                errors_total <- errors_total + 1;
            }
            write "";
        }
        write "──────────────────────────────────────────────";
        write "📊 RÉSULTAT FINAL :";
        write "- Shapes testées : " + string(nb_shapes_tested);
        write "- Erreurs : " + string(errors_total) + " (sur " + string(nb_shapes_tested) + " tests)";

        if (errors_total = 0) {
            write "🎉 TEST RÉUSSI : Tous les graphes sont cohérents avec leur polyligne.";
        } else {
            write "🚨 TEST ÉCHOUÉ : Problème de cohérence détecté !";
        }
    }
}

species transport_shape skills: [TransportShapeSkill] { }

experiment TestGrapheSegments type: gui {
    parameter "Dossier GTFS" var: gtfs_dir category: "Configuration";
    output {
        monitor "Shapes totales" value: nb_shapes_total;
        monitor "Shapes testées" value: nb_shapes_tested;
        monitor "Erreurs détectées" value: errors_total;
        monitor "Taux de réussite (%)" value: nb_shapes_tested > 0 ? (100.0 - (errors_total * 100.0 / nb_shapes_tested)) : 0.0;
    }
}
