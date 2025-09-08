model GraphesParShape

global {
    // --- Paramètres
    string gtfs_dir <- "../../includes/tisseo_gtfs_v2"; 
    
    // --- Variables globales
    gtfs_file gtfs_f;
    map<int, graph> shape_graphs <- [];
    int nb_shapes <- 0;
    int nb_graphes <- 0;
    int errors_total <- 0;
    
    // --- Initialisation
    init {
        write "🚍 Test – Génération des shapes et graphes";
        gtfs_f <- gtfs_file(gtfs_dir);
        if (gtfs_f = nil) {
            write "❌ Erreur : impossible de charger le GTFS.";
            do die;
        }
        
        create transport_shape from: gtfs_f;
        nb_shapes <- length(transport_shape);
        
        // Génération des graphes pour chaque shape
        write "🔄 Génération des graphes (as_edge_graph)";
        loop s over: transport_shape {
            shape_graphs[s.shapeId] <- as_edge_graph(s);
        }
        nb_graphes <- length(shape_graphs);
        
        write "✅ Initialisation terminée, vérification au prochain cycle...";
    }
    
    // --- Reflexe de test au cycle 2
    reflex test_graphes when: cycle = 2 {
        write "🔍 Test de correspondance shapeId <-> shape_graphs";
        errors_total <- 0;
        
        // Test 1 : même nombre de shapes et de graphes
        if (nb_shapes = nb_graphes) {
            write "✅ Nombre de graphes OK : " + string(nb_graphes) + "/" + string(nb_shapes);
        } else {
            write "❌ Erreur : " + string(nb_graphes) + " graphes pour " + string(nb_shapes) + " shapes.";
            errors_total <- errors_total + 1;
        }
        
        // Test 2 : chaque shapeId possède une entrée dans la map
        ask transport_shape {
            if not(shape_graphs contains_key shapeId) {
                write "❌ Graphe manquant pour shapeId : " + string(shapeId);
                errors_total <- errors_total + 1;
            }
        }
        
        // Test 3 : (optionnel) aucun "graphe orphelin" dans la map
        loop sid over: shape_graphs.keys {
            list<transport_shape> matching_shapes <- transport_shape where (each.shapeId = sid);
            int found <- length(matching_shapes);
            if (found = 0) {
                write "❌ Graphe sans shapeId correspondant : " + string(sid);
                errors_total <- errors_total + 1;
            }
        }
        
        // Résultat final
        if (errors_total = 0) {
            write "🎉 TEST Nombre des graphs RÉUSSI : Tous les shapes ont leur graphe, aucune incohérence.";
        } else {
            write "🚨 TEST Nombre des graphs ÉCHEC : " + string(errors_total) + " incohérence(s) détectée(s) !";
        }
    }
}

// --- Espèce transport_shape minimale (on se concentre sur le test)
species transport_shape skills: [TransportShapeSkill] {
    // shapeId est déjà défini dans TransportShapeSkill comme int
}

// --- Expérience ---
experiment TestGraphes type: gui {
    parameter "Dossier GTFS" var: gtfs_dir category: "Configuration";
    
    output {
        monitor "Shapes créés" value: nb_shapes;
        monitor "Graphes créés" value: nb_graphes;
        monitor "Erreurs détectées" value: errors_total;
    }
}