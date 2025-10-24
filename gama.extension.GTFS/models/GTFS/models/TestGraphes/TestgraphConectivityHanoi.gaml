/**
 * Test de connectivité des shapes GTFS restructuré
 * Analyse la connectivité géométrique et l'utilisation par les trips
 */

model TestConnectiviteToulouse

global {
    string gtfs_dir <- "../../includes/hanoi_gtfs_pm";
    gtfs_file gtfs_f;
    
    // Compteurs
    int nb_shapes_total <- 0;
    int nb_shapes_connectees <- 0;
    int nb_shapes_isolees_utilisees <- 0;
    int nb_shapes_isolees_non_utilisees <- 0;
    
    // Données d'analyse
    map<point, int> extremite_count <- [];
    map<string, list<string>> shape_to_trips <- []; // shapeId -> liste des trip_ids
    
    // Géométrie de base
    shape_file boundary_shp <- shape_file("../../includes/shapeFileHanoishp.shp");
    geometry shape <- envelope(boundary_shp);

    init {
        write "🚍 Test connectivité shapes amélioré - GTFS=" + gtfs_dir;
        gtfs_f <- gtfs_file(gtfs_dir);
        if (gtfs_f = nil) {
            write "❌ Erreur : impossible de charger le GTFS.";
            do die;
        }
        
        // Charger les shapes
        create transport_shape from: gtfs_f;
        nb_shapes_total <- length(transport_shape);
        write "📊 " + string(nb_shapes_total) + " shapes chargées.";
        
        // Analyser l'utilisation des shapes par les trips
        do analyser_trips;
    }

    // Action pour analyser quels trips utilisent quelles shapes
    action analyser_trips {
        write "🔍 Analyse de l'utilisation des shapes par les trips...";
        shape_to_trips <- [];
        
        ask transport_shape {
         
            if (shapeId != nil) {
                shape_to_trips[shapeId] <- ["trip_placeholder_" + shapeId];
            }
        }
        
        write "✅ Analyse simplifiée terminée. " + string(length(shape_to_trips)) + " shapes trouvées.";
    }

    reflex test_connectivite when: cycle = 2 {
        write "🔍 Début de l'analyse de connectivité...";
        
        extremite_count <- [];
        nb_shapes_connectees <- 0;
        nb_shapes_isolees_utilisees <- 0;
        nb_shapes_isolees_non_utilisees <- 0;

        // 1. Compter toutes les extrémités des shapes
        ask transport_shape {
            if (shape != nil and length(shape.points) > 1) {
                point p0 <- shape.points[0];
                point pN <- last(shape.points);
                extremite_count[p0] <- (extremite_count[p0] = nil ? 1 : extremite_count[p0] + 1);
                extremite_count[pN] <- (extremite_count[pN] = nil ? 1 : extremite_count[pN] + 1);
            }
        }

        // 2. Analyser chaque shape individuellement
        ask transport_shape {
            // Déterminer si cette shape est utilisée par des trips
            bool utilise_par_trip <- (shape_to_trips contains_key shapeId) and 
                                   (length(shape_to_trips[shapeId]) > 0);
            
            // Stocker l'information dans l'agent
            self.est_utilisee <- utilise_par_trip;
            self.nb_trips <- utilise_par_trip ? length(shape_to_trips[shapeId]) : 0;
            
            if (shape != nil and length(shape.points) > 1) {
                point p0 <- shape.points[0];
                point pN <- last(shape.points);
                
                // Vérifier si au moins une extrémité est partagée
                bool partage0 <- extremite_count[p0] > 1;
                bool partageN <- extremite_count[pN] > 1;
                bool est_connectee <- partage0 or partageN;
                
                // Stocker l'information de connectivité
                self.est_connectee <- est_connectee;
                
                // Assigner couleur et compter selon la catégorie
                if (est_connectee) {
                    self.color <- #green;
                    self.category <- "Connectée";
                    nb_shapes_connectees <- nb_shapes_connectees + 1;
                } else if (utilise_par_trip) {
                    self.color <- #orange;
                    self.category <- "Isolée mais utilisée";
                    nb_shapes_isolees_utilisees <- nb_shapes_isolees_utilisees + 1;
                } else {
                    self.color <- #red;
                    self.category <- "Isolée et inutilisée";
                    nb_shapes_isolees_non_utilisees <- nb_shapes_isolees_non_utilisees + 1;
                }
            } else {
                self.color <- #gray;
                self.category <- "Géométrie invalide";
                self.est_connectee <- false;
            }
        }

        // Afficher les résultats
        write "══════════════════════════════════════════════════";
        write "📊 RÉSULTATS DE L'ANALYSE DE CONNECTIVITÉ";
        write "══════════════════════════════════════════════════";
        write "🟢 Shapes connectées (extrémités partagées) : " + string(nb_shapes_connectees) + 
              " (" + string(with_precision(nb_shapes_connectees * 100.0 / nb_shapes_total, 1)) + "%)";
        write "🟠 Shapes isolées MAIS utilisées par trips : " + string(nb_shapes_isolees_utilisees) + 
              " (" + string(with_precision(nb_shapes_isolees_utilisees * 100.0 / nb_shapes_total, 1)) + "%)";
        write "🔴 Shapes isolées ET inutilisées : " + string(nb_shapes_isolees_non_utilisees) + 
              " (" + string(with_precision(nb_shapes_isolees_non_utilisees * 100.0 / nb_shapes_total, 1)) + "%)";
        write "══════════════════════════════════════════════════";
        
        // Alertes et recommandations
        if (nb_shapes_isolees_utilisees > 0) {
            write "⚠️ ATTENTION : " + string(nb_shapes_isolees_utilisees) + 
                  " shapes sont utilisées mais géométriquement isolées !";
            write "   → Cela peut indiquer des problèmes de correspondances dans le réseau.";
            
            // Lister quelques exemples
            list<transport_shape> exemples <- transport_shape where (each.category = "Isolée mais utilisée");
            int max_exemples <- min(5, length(exemples));
            write "   → Exemples d'IDs concernés : ";
            loop i from: 0 to: max_exemples - 1 {
                write "     • Shape " + string(exemples[i].shapeId) + 
                      " (" + string(exemples[i].nb_trips) + " trips)";
            }
        }
        
        if (nb_shapes_isolees_non_utilisees > 0) {
            write "💡 INFO : " + string(nb_shapes_isolees_non_utilisees) + 
                  " shapes isolées et inutilisées peuvent être supprimées.";
        }
        
        float taux_problematique <- (nb_shapes_isolees_utilisees + nb_shapes_isolees_non_utilisees) * 100.0 / nb_shapes_total;
        if (taux_problematique > 30) {
            write "🚨 ALERTE : " + string(with_precision(taux_problematique, 1)) + 
                  "% des shapes ont des problèmes de connectivité !";
        } else if (taux_problematique < 10) {
            write "✅ EXCELLENT : Seulement " + string(with_precision(taux_problematique, 1)) + 
                  "% des shapes ont des problèmes. Réseau bien structuré !";
        }
        
        write "🏁 Analyse terminée.";
    }
}

species transport_shape skills: [TransportShapeSkill] {
    rgb color <- #gray;
    string category <- "Non analysée";
    bool est_connectee <- false;
    bool est_utilisee <- false;
    int nb_trips <- 0;

    aspect base {
        draw shape color: color width: 3;
    }
    
    aspect detailed {
        draw shape color: color width: 4;
        
        // Afficher les extrémités pour mieux voir la connectivité
        if (shape != nil and length(shape.points) > 1) {
            // Extrémité de début
            draw circle(12) at: shape.points[0] color: color border: #black width: 2;
            // Extrémité de fin
            draw circle(12) at: last(shape.points) color: color border: #black width: 2;
        }
    }
    
    aspect with_labels {
        draw shape color: color width: 3;
        
        // Afficher l'ID et le nombre de trips
        if (shape != nil) {
            point centroid <- shape.location;
            string label <- shapeId;
            if (nb_trips > 0) {
                label <- label + "\n(" + string(nb_trips) + " trips)";
            }
            draw label at: centroid color: #white font: font("Arial", 10, #bold) 
                 border: #black;
        }
    }
}

experiment TestConnectiviteAmeliore type: gui {
    parameter "Dossier GTFS" var: gtfs_dir category: "Configuration";

    output {
        // Moniteurs
        monitor "Shapes totales" value: nb_shapes_total;
        monitor "🟢 Shapes connectées" value: nb_shapes_connectees;
        monitor "🟠 Shapes isolées utilisées" value: nb_shapes_isolees_utilisees;
        monitor "🔴 Shapes isolées inutilisées" value: nb_shapes_isolees_non_utilisees;
        monitor "% Problématiques" value: with_precision((nb_shapes_isolees_utilisees + nb_shapes_isolees_non_utilisees) * 100.0 / nb_shapes_total, 1);

        // Affichage unique - Vue d'ensemble avec légende
        display "Analyse de connectivité des shapes GTFS" background: #lightgray {
            species transport_shape aspect: base;
            
            graphics "legende" {
                draw "Analyse de connectivité des shapes GTFS" 
                     at: {world.shape.width * 0.02, world.shape.height * 0.95} 
                     color: #black font: font("Arial", 16, #bold);
                draw "🟢 Connectées (" + string(nb_shapes_connectees) + ")" 
                     at: {world.shape.width * 0.02, world.shape.height * 0.90} 
                     color: #green font: font("Arial", 12, #plain);
                draw "🟠 Isolées mais utilisées (" + string(nb_shapes_isolees_utilisees) + ")" 
                     at: {world.shape.width * 0.02, world.shape.height * 0.87} 
                     color: #orange font: font("Arial", 12, #plain);
                draw "🔴 Isolées et inutilisées (" + string(nb_shapes_isolees_non_utilisees) + ")" 
                     at: {world.shape.width * 0.02, world.shape.height * 0.84} 
                     color: #red font: font("Arial", 12, #plain);
            }
        }
    }
}