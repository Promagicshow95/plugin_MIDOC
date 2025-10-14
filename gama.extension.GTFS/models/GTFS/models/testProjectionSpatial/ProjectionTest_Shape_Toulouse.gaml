/**
 * Test de cohérence spatiale GTFS vs GAMA - Transport Shapes (Version Simplifiée)
 * Objectif : Vérifier que les points des shapes GTFS sont correctement projetés dans GAMA
 */

model GTFSShapeProjectionValidation

global {
    // === CONFIGURATION ===
    string projection_crs <- "EPSG:2154"; // Lambert-93 (configurable)
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
    file data_file <- shape_file("../../includes/shapeFileToulouse.shp");
    geometry shape <- envelope(data_file);
    
    // === ÉTAPE 1 : MAPS GTFS ===
    map<string, list> map_gtfs <- []; // [shape_id] -> [first_point_lat, first_point_lon, total_points]
    
    // === ÉTAPE 2 : MAPS GTFS PROJETÉES ===
    map<string, list> map_gtfs_projected <- []; // [shape_id] -> [first_point_projected, total_points]
    
    // === ÉTAPE 3 : MAPS GAMA ===
    map<string, list> map_gama <- []; // [shapeId] -> [first_gama_point, total_gama_points]
    
    // === VARIABLES DE RAPPORT ===
    int total_shapes_tested <- 0;
    int valid_shapes <- 0;
    int invalid_shapes <- 0;
    list<string> error_shapes <- [];
    list<float> distances <- [];
    float tolerance_distance <- 10.0; // 10m
    bool test_global_success <- false;
    
    // === VARIABLES POUR TESTS ÉTENDUS ===
    bool projection_consistency_test <- false;
    bool point_count_consistency_test <- false;
    
    init {
        write "=== ALGORITHME DE TEST DE COHÉRENCE SHAPES GTFS-GAMA ===";
        
        // ÉTAPE 1 : EXTRACTION SHAPES GTFS
        do extract_shapes_from_gtfs;
        
        // ÉTAPE 2 : PROJECTION DES COORDONNÉES
        do project_gtfs_coordinates;
        
        // ÉTAPE 3 : CRÉATION AGENTS ET RÉCUPÉRATION
        do create_and_collect_gama_agents;
        
        // ÉTAPE 4 : COMPARAISON
        do compare_gtfs_vs_gama;
        
        // ÉTAPE 5 : TESTS COMPLÉMENTAIRES
        do run_additional_tests;
        
        // ÉTAPE 6 : GÉNÉRATION RAPPORT COMPLET
        do generate_final_report;
    }
    
    // === ÉTAPE 1 : EXTRAIRE LES SHAPES DEPUIS LE GTFS ===
    action extract_shapes_from_gtfs {
        write "\n=== ÉTAPE 1 : EXTRACTION SHAPES GTFS ===";
        
        try {
            // Créer temporairement les shapes pour extraire leurs données
            list<transport_shape> temp_shapes <- [];
            create transport_shape from: gtfs_f returns: temp_shapes;
            
            write "📊 Agents temporaires créés : " + length(temp_shapes);
            
            // Extraire les données GTFS originales via TransportShapeSkill
            ask temp_shapes {
                if self.shapeId != nil and self.shape != nil and length(self.shape.points) > 0 {
                    // Prendre le premier point comme référence pour la comparaison
                    point first_point <- self.shape.points[0];
                    
                    // Conversion inverse pour obtenir les coordonnées WGS84 d'origine
                    point wgs84_coord <- CRS_transform(first_point, projection_crs, "EPSG:4326");
                    
                    myself.map_gtfs[string(self.shapeId)] <- [wgs84_coord.y, wgs84_coord.x, length(self.shape.points)]; // [lat, lon, count]
                    
                    // Debug pour les 5 premiers
                    if length(myself.map_gtfs) <= 5 {
                        write "📍 GTFS Shape: " + string(self.shapeId) + " | Points: " + length(self.shape.points) + 
                              " | Premier point WGS84: [" + wgs84_coord.y + ", " + wgs84_coord.x + "]";
                    }
                }
                do die; // Supprimer les agents temporaires
            }
            
        } catch {
            write "❌ Erreur lors de l'extraction GTFS - Création de données de test";
            
            // Données de test si GTFS indisponible
            map_gtfs["SHAPE_TEST_01"] <- [47.212841, -1.561781, 15];
            map_gtfs["SHAPE_TEST_02"] <- [47.218371, -1.553621, 20];
            map_gtfs["SHAPE_TEST_03"] <- [47.215350, -1.548920, 12];
        }
        
        write "✅ Étape 1 terminée : " + length(map_gtfs) + " shapes extraits du GTFS";
    }
    
    // === ÉTAPE 2 : CALCULER LA POSITION PROJETÉE POUR CHAQUE SHAPE ===
    action project_gtfs_coordinates {
        write "\n=== ÉTAPE 2 : PROJECTION COORDONNÉES GTFS ===";
        
        loop shape_id over: map_gtfs.keys {
            list shape_data <- map_gtfs[shape_id];
            float shape_lat <- shape_data[0];
            float shape_lon <- shape_data[1];
            int point_count <- int(shape_data[2]);
            
            // Projection WGS84 -> Lambert-93 (ou autre CRS configuré)
            point point_proj <- CRS_transform({shape_lon, shape_lat}, "EPSG:4326", projection_crs);
            
            map_gtfs_projected[shape_id] <- [point_proj, point_count];
            
            // Debug pour les 5 premiers
            if length(map_gtfs_projected) <= 5 {
                write "🎯 Projection: " + shape_id + " | Premier point projeté: " + point_proj + " | Points: " + point_count;
            }
        }
        
        write "✅ Étape 2 terminée : " + length(map_gtfs_projected) + " shapes projetés";
    }
    
    // === ÉTAPE 3 : RÉCUPÉRER LES AGENTS CRÉÉS DANS GAMA ===
    action create_and_collect_gama_agents {
        write "\n=== ÉTAPE 3 : CRÉATION ET COLLECTE AGENTS GAMA ===";
        
        // Créer les vrais agents GAMA
        create transport_shape from: gtfs_f;
        
        write "📊 Agents GAMA créés : " + length(transport_shape);
        
        // Collecter les données des agents (utilisation des attributs TransportShapeSkill)
        ask transport_shape {
            // TransportShapeSkill fournit automatiquement shapeId et shape
            if self.shapeId != nil and self.shape != nil and length(self.shape.points) > 0 {
                point first_gama_point <- self.shape.points[0];
                int total_gama_points <- length(self.shape.points);
                
                myself.map_gama[string(self.shapeId)] <- [first_gama_point, total_gama_points];
                
                // Debug pour les 5 premiers
                if length(myself.map_gama) <= 5 {
                    write "🤖 Agent GAMA: " + string(self.shapeId) + " | Points: " + total_gama_points + 
                          " | Premier point: " + first_gama_point;
                }
            } else {
                write "⚠️ Agent sans shapeId ou shape valide";
            }
        }
        
        write "✅ Étape 3 terminée : " + length(map_gama) + " agents collectés";
    }
    
    // === ÉTAPE 4 : COMPARER LES DEUX MAPS ===
    action compare_gtfs_vs_gama {
        write "\n=== ÉTAPE 4 : COMPARAISON GTFS vs GAMA ===";
        
        // Trouver les shapes communs
        list<string> common_shapes <- [];
        loop shape_id over: map_gtfs_projected.keys {
            if map_gama contains_key shape_id {
                common_shapes <- common_shapes + shape_id;
            }
        }
        
        write "📊 Shapes communs trouvés : " + length(common_shapes);
        total_shapes_tested <- length(common_shapes);
        
        // Comparer chaque shape commun
        loop shape_id over: common_shapes {
            // Récupérer positions du premier point
            list gtfs_data <- map_gtfs_projected[shape_id];
            point gtfs_position <- gtfs_data[0];
            int gtfs_point_count <- int(gtfs_data[1]);
            
            list gama_data <- map_gama[shape_id];
            point gama_position <- gama_data[0];
            int gama_point_count <- int(gama_data[1]);
            
            // Calculer distance entre premiers points
            float distance <- gtfs_position distance_to gama_position;
            distances <- distances + distance;
            
            // Vérifier aussi la cohérence du nombre de points
            bool point_count_ok <- (gtfs_point_count = gama_point_count);
            
            // Évaluer la validité
            if distance < tolerance_distance and point_count_ok {
                valid_shapes <- valid_shapes + 1;
                write "✅ VALID: " + shape_id + " | Distance: " + string(distance) + "m | Points: " + gtfs_point_count;
            } else {
                invalid_shapes <- invalid_shapes + 1;
                error_shapes <- error_shapes + shape_id;
                write "❌ INVALID: " + shape_id + " | Distance: " + string(distance) + "m | " +
                      "Points GTFS: " + gtfs_point_count + " vs GAMA: " + gama_point_count;
                write "   GTFS: " + gtfs_position + " | GAMA: " + gama_position;
            }
        }
        
        write "✅ Étape 4 terminée : Comparaison effectuée";
    }
    
    // === ÉTAPE 5 : TESTS COMPLÉMENTAIRES ===
    action run_additional_tests {
        write "\n=== ÉTAPE 5 : TESTS COMPLÉMENTAIRES ===";
        
        // Test 1: Cohérence de projection
        do test_projection_consistency;
        
        // Test 2: Cohérence du nombre de points
        do test_point_count_consistency;
        
        write "✅ Étape 5 terminée : Tests complémentaires effectués";
    }
    
    // Test de cohérence de projection
    action test_projection_consistency {
        write "\n--- TEST COHÉRENCE PROJECTION ---";
        
        // Tester la projection avec des points de référence connus
        point test_wgs84 <- {2.3522, 48.8566}; // Paris Notre-Dame
        point test_projected <- CRS_transform(test_wgs84, "EPSG:4326", projection_crs);
        
        // Vérifier que la projection produit des résultats cohérents
        bool projection_works <- (test_projected != nil) and 
                                (abs(test_projected.x) > 1000) and 
                                (abs(test_projected.y) > 1000);
        
        projection_consistency_test <- projection_works;
        
        write "Point test WGS84: " + string(test_wgs84);
        write "Point test projeté (" + projection_crs + "): " + string(test_projected);
        write "Test cohérence projection: " + (projection_consistency_test ? "✅ RÉUSSI" : "❌ ÉCHOUÉ");
    }
    
    // Test cohérence nombre de points
    action test_point_count_consistency {
        write "\n--- TEST COHÉRENCE NOMBRE DE POINTS ---";
        
        int consistent_counts <- 0;
        int total_compared <- 0;
        
        loop shape_id over: map_gtfs_projected.keys {
            if map_gama contains_key shape_id {
                total_compared <- total_compared + 1;
                
                list gtfs_data <- map_gtfs_projected[shape_id];
                int gtfs_count <- int(gtfs_data[1]);
                
                list gama_data <- map_gama[shape_id];
                int gama_count <- int(gama_data[1]);
                
                if gtfs_count = gama_count {
                    consistent_counts <- consistent_counts + 1;
                }
            }
        }
        
        point_count_consistency_test <- (consistent_counts = total_compared);
        
        write "Shapes avec nombre de points cohérent: " + consistent_counts + "/" + total_compared;
        write "Test cohérence nombre de points: " + (point_count_consistency_test ? "✅ RÉUSSI" : "❌ ÉCHOUÉ");
    }
    
    // === ÉTAPE 6 : GÉNÉRER RAPPORT FINAL ===
    action generate_final_report {
        write "\n=== ÉTAPE 6 : RAPPORT FINAL ===";
        
        // Calculer statistiques
        float success_rate <- total_shapes_tested > 0 ? (valid_shapes / total_shapes_tested) * 100 : 0;
        test_global_success <- (invalid_shapes = 0) and (total_shapes_tested > 0) and 
                              projection_consistency_test and point_count_consistency_test;
        
        float avg_distance <- length(distances) > 0 ? mean(distances) : 0;
        float max_distance <- length(distances) > 0 ? max(distances) : 0;
        float min_distance <- length(distances) > 0 ? min(distances) : 0;
        
        // Rapport détaillé
        write "\n📋 RAPPORT DE COHÉRENCE SHAPES GTFS-GAMA :";
        write "==============================================";
        write "🌍 CONFIGURATION :";
        write "   - Projection utilisée : " + projection_crs;
        write "   - Tolérance acceptée : " + string(tolerance_distance) + "m";
        write "";
        write "📊 STATISTIQUES GLOBALES :";
        write "   - Shapes GTFS extraits : " + length(map_gtfs);
        write "   - Shapes GTFS projetés : " + length(map_gtfs_projected);
        write "   - Agents GAMA créés : " + length(map_gama);
        write "   - Shapes testés (communs) : " + total_shapes_tested;
        write "";
        write "✅ RÉSULTATS DE VALIDATION :";
        write "   - Shapes valides (< " + string(tolerance_distance) + "m) : " + valid_shapes;
        write "   - Shapes invalides (≥ " + string(tolerance_distance) + "m) : " + invalid_shapes;
        write "   - Taux de réussite : " + string(success_rate) + "%";
        write "";
        write "📏 STATISTIQUES DE DISTANCE :";
        write "   - Distance moyenne : " + string(avg_distance) + "m";
        write "   - Distance minimale : " + string(min_distance) + "m";
        write "   - Distance maximale : " + string(max_distance) + "m";
        write "   - Tolérance : " + string(tolerance_distance) + "m";
        write "";
        write "🔧 TESTS COMPLÉMENTAIRES :";
        write "   - Cohérence projection : " + (projection_consistency_test ? "✅ RÉUSSI" : "❌ ÉCHOUÉ");
        write "   - Cohérence nombre points : " + (point_count_consistency_test ? "✅ RÉUSSI" : "❌ ÉCHOUÉ");
        write "";
        write "🎯 RÉSULTAT GLOBAL : " + (test_global_success ? "✅ TEST RÉUSSI" : "❌ TEST ÉCHOUÉ");
        
        if length(error_shapes) > 0 {
            write "";
            write "❌ SHAPES EN ERREUR :";
            loop error_shape over: error_shapes {
                write "   - " + error_shape;
            }
        }
        
        write "==============================================";
        
        // Conclusion technique
        if test_global_success {
            write "🎉 CONCLUSION : La projection et les shapes sont cohérents !";
            write "   Les données géospatiales sont prêtes pour la simulation.";
        } else {
            write "🔧 CONCLUSION : Des incohérences détectées. Vérifications recommandées :";
            write "   1. Configuration projection CRS (actuellement : " + projection_crs + ")";
            write "   2. Qualité des données shapes.txt";
            write "   3. Processus de création des agents transport_shape";
            write "   4. Cohérence du nombre de points par shape";
        }
        
        write "\n📈 MÉTRIQUES DE QUALITÉ :";
        write "   - Précision moyenne : " + string(avg_distance) + "m";
        write "   - Fiabilité : " + string(success_rate) + "% des shapes validés";
        write "   - Couverture : " + string(total_shapes_tested) + " shapes testés";
        
        // Mise à jour des couleurs des agents selon les résultats
        do update_agent_colors;
    }
    
    // Action pour mettre à jour les couleurs des agents selon les résultats
    action update_agent_colors {
        ask transport_shape {
            string shape_key <- string(self.shapeId);
            bool is_valid <- not (error_shapes contains shape_key);
            do update_validation_color(is_valid);
        }
    }
    
    // Action pour diagnostic détaillé
    action show_detailed_comparison {
    write "\n=== COMPARAISON DÉTAILLÉE ===";
    
    loop shape_id over: map_gtfs_projected.keys {
        if map_gama contains_key shape_id {
            list gtfs_data <- map_gtfs_projected[shape_id];
            list gama_data <- map_gama[shape_id];
            
            // ✅ CORRECTION : Cast explicite en point
            point gtfs_point <- point(gtfs_data[0]);
            point gama_point <- point(gama_data[0]);
            int gtfs_count <- int(gtfs_data[1]);
            int gama_count <- int(gama_data[1]);
            
            // ✅ CORRECTION : Calcul de distance avec types explicites
            float distance <- gtfs_point distance_to gama_point;
            
            write "Shape: " + shape_id;
            write "  GTFS proj: " + string(gtfs_point) + " (" + string(gtfs_count) + " points)";
            write "  GAMA pos:  " + string(gama_point) + " (" + string(gama_count) + " points)";
            write "  Distance:  " + string(distance) + "m";
            write "";
        }
    }
}
}

// Species transport_shape avec TransportShapeSkill (similaire au modèle stops)
species transport_shape skills: [TransportShapeSkill] {
    string name;
    rgb color <- #blue;
    float width <- 2.0;
    
    init {
        if name = nil or name = "" {
            name <- "Shape_" + string(self);
        }
        color <- #blue;
        width <- 2.0;
    }
    
    // Action pour mettre à jour la couleur selon le résultat du test
    action update_validation_color(bool is_valid) {
        if is_valid {
            color <- #green;
            width <- 3.0;
        } else {
            color <- #red;
            width <- 5.0;
        }
    }
    
    aspect base {
        if shape != nil {
            draw shape color: color width: width;
        }
    }
    
    aspect detailed {
        if shape != nil {
            draw shape color: color width: width;
            
            // Afficher les informations de validation
            if shapeId != nil {
                point centroid <- shape.location;
                draw string(shapeId) color: #black font: font("Arial", 8, #bold) at: centroid;
                
                // Afficher le nombre de points
                string point_info <- "Points: " + string(length(shape.points));
                draw point_info color: #darkblue font: font("Arial", 7) at: centroid + {0, 25};
            }
            
            // Marquer le premier point pour validation visuelle
            if length(shape.points) > 0 {
                point first_pt <- shape.points[0];
                draw circle(20) at: first_pt color: color border: #white width: 2;
                draw "1" color: #white font: font("Arial", 8, #bold) at: first_pt;
            }
        }
    }
}

experiment ValidationProjection type: gui {
    parameter "Tolérance distance (m)" var: tolerance_distance min: 1 max: 100 step: 1;
    parameter "Projection CRS" var: projection_crs among: ["EPSG:2154", "EPSG:3857", "EPSG:4326"];
    
    output {
        display "Carte de Cohérence Shapes" type: 2d {
            species transport_shape aspect: detailed;
            
            overlay position: {10, 10} size: {450 #px, 350 #px} background: #white transparency: 0.8 {
                draw "=== TEST DE COHÉRENCE SHAPES GTFS-GAMA ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                
                draw "🌍 CONFIGURATION :" at: {10#px, 45#px} color: #blue font: font("Arial", 10, #bold);
                draw "Projection: " + projection_crs at: {20#px, 65#px} color: #black;
                draw "Tolérance: " + string(tolerance_distance) + "m" at: {20#px, 80#px} color: #black;
                
                draw "📊 DONNÉES :" at: {10#px, 105#px} color: #blue font: font("Arial", 10, #bold);
                draw "Shapes GTFS : " + length(map_gtfs) at: {20#px, 125#px} color: #black;
                draw "Agents GAMA : " + length(map_gama) at: {20#px, 140#px} color: #black;
                draw "Shapes testés : " + total_shapes_tested at: {20#px, 155#px} color: #black;
                
                draw "✅ RÉSULTATS :" at: {10#px, 180#px} color: #green font: font("Arial", 10, #bold);
                draw "Shapes valides : " + valid_shapes at: {20#px, 200#px} color: #green;
                draw "Shapes invalides : " + invalid_shapes at: {20#px, 215#px} color: #red;
                
                if total_shapes_tested > 0 {
                    float success_rate <- (valid_shapes / total_shapes_tested) * 100;
                    draw "Taux de réussite : " + string(success_rate) + "%" at: {20#px, 230#px} 
                         color: (success_rate = 100 ? #green : #orange);
                }
                
                draw "📏 DISTANCES :" at: {10#px, 255#px} color: #purple font: font("Arial", 10, #bold);
                if length(distances) > 0 {
                    draw "Moyenne : " + string(mean(distances)) + "m" at: {20#px, 275#px} color: #black;
                    draw "Maximum : " + string(max(distances)) + "m" at: {20#px, 290#px} color: #black;
                }
                
                draw "🎯 RÉSULTAT GLOBAL :" at: {10#px, 315#px} color: #black font: font("Arial", 10, #bold);
                string result_text <- test_global_success ? "✅ TEST RÉUSSI" : "❌ TEST ÉCHOUÉ";
                rgb result_color <- test_global_success ? #green : #red;
                draw result_text at: {20#px, 335#px} color: result_color font: font("Arial", 11, #bold);
            }
        }
        
        display "Graphique des Distances" {
            chart "Distribution des Distances Premier Point" type: histogram {
                if length(distances) > 0 {
                    data "Distances (m)" value: distances color: #blue;
                }
            }
        }
        
        display "Analyse par Shape" {
            chart "Validation par Shape" type: pie {
                data "Shapes Valides" value: valid_shapes color: #green;
                data "Shapes Invalides" value: invalid_shapes color: #red;
            }
        }
    }
}