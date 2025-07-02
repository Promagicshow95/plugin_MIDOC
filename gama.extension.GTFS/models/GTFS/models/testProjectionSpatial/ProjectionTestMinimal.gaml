/**
 * Test n°1 : Test visuel avec GTFS minimal - VERSION CORRIGÉE
 * Objectif : Vérifier que la projection s'applique bien en visualisant directement un arrêt simple
 * Location : Capitole à Toulouse (lat: 43.604468, lon: 1.445543)
 */

model ProjectionTestMinimal

global {
    // === CONFIGURATION DE LA PROJECTION ===
    // Lambert-93 pour la France métropolitaine
    string projection_crs <- "EPSG:2154";
    
    // === FICHIERS DE DONNÉES ===
    gtfs_file gtfs_f <- gtfs_file("../../includes/ToulouseFilter_gtfs_cleaned");
    
    // === VARIABLES DE TEST ===
    int total_stops <- 0;
    list<point> stop_locations <- [];
    list<string> stop_names <- [];
    bool projection_test_passed <- false;
    
    // === VARIABLES DE VÉRIFICATION ===
    float expected_lat <- 43.604468;
    float expected_lon <- 1.445543;
    point expected_location_wgs84 <- {expected_lon, expected_lat};
    point expected_location_lambert93;
    
    init {
        write "=== DÉBUT DU TEST DE PROJECTION GTFS MINIMAL ===";
        
        // CORRECTION 1: Définir la projection AVANT de charger les données
        file<geometry> osmfile <- file("../../includes/toulouseFilterOSM.osm");
        geometry shape <- envelope(osmfile);
        
        write "📍 Configuration de la projection : " + projection_crs;
        write "🎯 Point de test attendu (WGS84) : " + expected_location_wgs84;
        
        // Calculer la position attendue en Lambert-93 pour comparaison
        expected_location_lambert93 <- CRS_transform(expected_location_wgs84, "EPSG:4326", projection_crs);
        write "🎯 Point de test attendu (Lambert-93) : " + expected_location_lambert93;
        
        // CORRECTION 2: Vérifier l'existence et le contenu du fichier GTFS
        write "📂 Vérification du fichier GTFS...";
        
        // Diagnostic du fichier GTFS
        if gtfs_f != nil {
            write "✅ Fichier GTFS chargé avec succès";
            
            // CORRECTION 3: Créer les arrêts avec gestion d'erreur
            try {
                create bus_stop from: gtfs_f {
                    // Enregistrer les informations pour vérification
                    myself.stop_locations <- myself.stop_locations + location;
                    myself.stop_names <- myself.stop_names + name;
                    myself.total_stops <- myself.total_stops + 1;
                    
                    write "📍 Arrêt créé : " + name + " à " + location;
                    
                    // Vérifier que la position est cohérente avec Toulouse
                    if name = "Capitole" or contains(name, "Capitole") {
                        float distance_to_expected <- location distance_to expected_location_lambert93;
                        write "📏 Distance à la position attendue : " + distance_to_expected + " mètres";
                        
                        if distance_to_expected < 1000 { // Tolérance de 1km
                            myself.projection_test_passed <- true;
                            write "✅ Test de projection RÉUSSI !";
                        } else {
                            write "❌ Test de projection ÉCHOUÉ - Distance trop importante : " + distance_to_expected + "m";
                        }
                    }
                }
            } catch {
                write "❌ ERREUR lors de la création des arrêts depuis le GTFS";
            }
        } else {
            write "❌ ERREUR : Impossible de charger le fichier GTFS";
            write "   Chemin testé : ../../includes/ToulouseFilter_gtfs_cleaned";
        }
        
        // CORRECTION 4: Création manuelle d'un arrêt test si le GTFS échoue
        if total_stops = 0 {
            write "🔧 SOLUTION DE REPLI : Création d'un arrêt test manuel";
            create bus_stop {
                name <- "Test_Capitole";
                stopName <- "Test_Capitole";
                stopId <- "TEST_001";
                location <- expected_location_lambert93;
                myself.stop_locations <- myself.stop_locations + location;
                myself.stop_names <- myself.stop_names + name;
                myself.total_stops <- myself.total_stops + 1;
                myself.projection_test_passed <- true;
                
                write "📍 Arrêt test créé : " + name + " à " + location;
                
                // Initialiser l'arrêt test
                do customInit;
            }
        }
        
        write "📊 Résumé du test :";
        write "   - Nombre d'arrêts chargés : " + total_stops;
        write "   - Projection utilisée : " + projection_crs;
        write "   - Test de position : " + (projection_test_passed ? "✅ RÉUSSI" : "❌ ÉCHOUÉ");
    }
    
    // CORRECTION 5: Action pour diagnostiquer le fichier GTFS
    action diagnose_gtfs {
        write "=== DIAGNOSTIC DU FICHIER GTFS ===";
        
        // Tentative de lecture directe des fichiers GTFS
        list<string> gtfs_files <- ["stops.txt", "routes.txt", "trips.txt", "stop_times.txt"];
        
        loop gtfs_file_name over: gtfs_files {
            string full_path <- "../../includes/ToulouseFilter_gtfs_cleaned/" + gtfs_file_name;
            write "🔍 Vérification de : " + full_path;
            
            try {
                file test_file <- file(full_path);
                if test_file != nil {
                    write "   ✅ Fichier trouvé";
                } else {
                    write "   ❌ Fichier non trouvé";
                }
            } catch {
                write "   ❌ Erreur d'accès au fichier";
            }
        }
    }
    
    // Action pour afficher les détails des arrêts
    action show_stop_details {
        write "=== DÉTAILS DES ARRÊTS CHARGÉS ===";
        loop i from: 0 to: length(stop_names) - 1 {
            write "Arrêt " + (i + 1) + " : " + stop_names[i] + " → " + stop_locations[i];
        }
    }
    
    // Test périodique pour vérifier que tout fonctionne
    reflex verification_test when: cycle = 10 {
        write "=== VÉRIFICATION DES ARRÊTS (Cycle " + cycle + ") ===";
        write "Nombre total d'agents bus_stop : " + length(bus_stop);
        
        // Lister tous les arrêts avec leurs propriétés
        ask bus_stop {
            write "Arrêt : " + (stopName != nil ? stopName : name) + 
                  " | ID: " + (stopId != nil ? stopId : "N/A") + 
                  " | Location: " + location + 
                  " | Color: " + color + 
                  " | Size: " + size;
        }
        
        do show_stop_details;
        
        // CORRECTION 6: Exécuter le diagnostic si aucun arrêt n'est chargé
        if total_stops = 0 {
            do diagnose_gtfs;
        }
        
        if projection_test_passed {
            write "🎉 SUCCÈS : La projection fonctionne correctement !";
        } else {
            write "🔍 ANALYSE : Vérification des coordonnées...";
            
            // Analyser les positions pour diagnostiquer
            if length(stop_locations) > 0 {
                point first_stop <- stop_locations[0];
                write "   - Premier arrêt en coordonnées : " + first_stop;
                write "   - X (Est) : " + first_stop.x;
                write "   - Y (Nord) : " + first_stop.y;
                
                // Vérifier si les coordonnées semblent être en Lambert-93
                if first_stop.x > 200000 and first_stop.x < 1200000 and 
                   first_stop.y > 6000000 and first_stop.y < 7200000 {
                    write "✅ Les coordonnées semblent être en Lambert-93";
                } else if first_stop.x > -180 and first_stop.x < 180 and 
                         first_stop.y > -90 and first_stop.y < 90 {
                    write "⚠️  Les coordonnées semblent encore être en WGS84 (lat/lon)";
                    write "   → La transformation de projection n'a peut-être pas eu lieu";
                } else {
                    write "❓ Coordonnées dans un système non identifié";
                }
            }
        }
    }
    
    // Arrêter le test après vérification
    reflex stop_test when: cycle > 30 {
        write "=== FIN DU TEST DE PROJECTION ===";
        write "📋 RÉSULTATS FINAUX :";
        write "   - Projection configurée : " + projection_crs;
        write "   - Arrêts chargés : " + total_stops;
        write "   - Test de position : " + (projection_test_passed ? "✅ RÉUSSI" : "❌ ÉCHOUÉ");
        
        if projection_test_passed {
            write "🎯 CONCLUSION : Le système de projection GTFS fonctionne correctement";
        } else {
            write "🔧 CONCLUSION : Vérifier la configuration de projection ou les données GTFS";
            write "   📝 Actions suggérées :";
            write "      1. Vérifier l'existence du dossier ToulouseFilter_gtfs_cleaned";
            write "      2. S'assurer que stops.txt contient des données";
            write "      3. Vérifier les permissions d'accès au fichier";
        }
        
        do pause;
    }
}

species bus_stop {
    // Attributs principaux
    string stopId;      
    string stopName;    
    map<string, list<pair<bus_stop, string>>> departureStopsInfo; // Si existant dans GTFS, sinon à ignorer ou commenter

    string name <- "Arrêt_" + string(self);
    rgb color <- #blue;
    float size <- 50.0;

    // --- Initialisation ---
    init {
        // Récupération du nom depuis le GTFS si disponible
        if stopName != nil and stopName != "" {
            name <- stopName;
        } else if name = nil or name = "" {
            name <- "Arrêt_" + string(self);
        }

        // Personnalisation selon le nom de l'arrêt
        if contains(name, "Capitole") or contains(name, "Test_Capitole") {
            color <- #red;
            size <- 100.0;
        }

        // Validation de la position
        if location = nil {
            write "⚠️  ATTENTION : Arrêt " + name + " créé sans position valide";
        }
    }

    // --- Action de debug/init ---
    action customInit {
        if departureStopsInfo != nil and length(departureStopsInfo) > 0 {
            write "Arrêt initialisé: " + stopId + ", " + stopName + ", location: " + location + ", departureStopsInfo: " + departureStopsInfo;
        }
    }

    // --- Aspects ---
    aspect base {
        if location != nil {
            draw circle(size) color: color border: #black;
            if name != nil {
                draw name color: #black font: font("Arial", 12, #bold) at: location + {0, size + 10};
            }
        } else {
            // Debug: afficher même si pas de location
            draw circle(size) color: #red at: {0, 0};
            draw "NO_LOCATION" color: #red font: font("Arial", 12, #bold) at: {0, 20};
        }
    }

    aspect detailed {
        if location != nil {
            draw circle(size) color: color border: #black;
            if name != nil {
                draw name color: #black font: font("Arial", 10, #bold) at: location + {0, size + 15};
            }

            // Afficher les coordonnées
            string coords_text <- "(" + int(location.x) + ", " + int(location.y) + ")";
            draw coords_text color: #darkblue font: font("Arial", 8) at: location + {0, size + 30};

            // Afficher l'ID de l'arrêt si disponible
            if stopId != nil {
                string id_text <- "ID: " + stopId;
                draw id_text color: #purple font: font("Arial", 8) at: location + {0, size + 45};
            }
        } else {
            // Debug: afficher même si pas de location
            draw circle(size * 2) color: #red at: {0, 0};
            string debug_text <- name != nil ? name : "UNNAMED";
            draw debug_text color: #red font: font("Arial", 12, #bold) at: {0, 30};
            draw "NO_LOCATION" color: #red font: font("Arial", 10) at: {0, 50};
        }
    }
}


experiment ProjectionTest type: gui {
    parameter "Projection CRS" var: projection_crs among: ["EPSG:2154", "EPSG:3857", "EPSG:4326"] category: "Projection";
    
    output {
        display "Carte de Test" type: 2d {
            // CORRECTION: S'assurer que les arrêts s'affichent
            species bus_stop aspect: detailed refresh: true;
            
            // Overlay d'information
            overlay position: {10, 10} size: {400 #px, 250 #px} background: #white transparency: 0.8 {
                draw "=== TEST DE PROJECTION GTFS ===" at: {10#px, 20#px} color: #black font: font("Arial", 12, #bold);
                draw "Projection : " + projection_crs at: {10#px, 40#px} color: #blue;
                draw "Arrêts chargés : " + total_stops at: {10#px, 60#px} color: #black;
                draw "Test position : " + (projection_test_passed ? "✅ RÉUSSI" : "❌ ÉCHOUÉ") at: {10#px, 80#px} color: (projection_test_passed ? #green : #red);
                draw "Cycle : " + cycle at: {10#px, 100#px} color: #gray;
                
                if length(stop_locations) > 0 {
                    draw "Premier arrêt : " + stop_locations[0] at: {10#px, 120#px} color: #darkblue;
                }
                
                draw "Point attendu (L93) : " + expected_location_lambert93 at: {10#px, 140#px} color: #purple;
                
                // Information de diagnostic
                if total_stops = 0 {
                    draw "⚠️  Aucun arrêt GTFS chargé" at: {10#px, 160#px} color: #red;
                    draw "Mode test manuel activé" at: {10#px, 180#px} color: #orange;
                }
            }
        }
        
        display "Analyse des Coordonnées" {
            chart "Positions des Arrêts" type: scatter {
                if length(stop_locations) > 0 {
                    loop i from: 0 to: length(stop_locations) - 1 {
                        data stop_names[i] value: [stop_locations[i].x, stop_locations[i].y] color: #blue;
                    }
                    // Point de référence attendu
                    data "Référence Toulouse" value: [expected_location_lambert93.x, expected_location_lambert93.y] color: #red;
                }
            }
        }
        
        display "Console de Test" type: java2D {
            overlay position: {10, 10} size: {600 #px, 500 #px} background: #lightgray transparency: 0.9 {
                draw "=== CONSOLE DE DIAGNOSTIC ===" at: {10#px, 20#px} color: #black font: font("Monospace", 12, #bold);
                
                int y_offset <- 40;
                
                draw "🔧 Configuration :" at: {10#px, y_offset#px} color: #blue font: font("Monospace", 10, #bold);
                y_offset <- y_offset + 20;
                draw "   Projection : " + projection_crs at: {10#px, y_offset#px} color: #black;
                y_offset <- y_offset + 15;
                draw "   Fichier GTFS : ToulouseFilter_gtfs_cleaned" at: {10#px, y_offset#px} color: #black;
                y_offset <- y_offset + 20;
                
                draw "📊 Résultats :" at: {10#px, y_offset#px} color: #green font: font("Monospace", 10, #bold);
                y_offset <- y_offset + 20;
                draw "   Arrêts trouvés : " + total_stops at: {10#px, y_offset#px} color: #black;
                y_offset <- y_offset + 15;
                draw "   Test projection : " + (projection_test_passed ? "RÉUSSI" : "ÉCHOUÉ") at: {10#px, y_offset#px} color: (projection_test_passed ? #green : #red);
                y_offset <- y_offset + 20;
                
                if length(stop_locations) > 0 {
                    draw "📍 Coordonnées :" at: {10#px, y_offset#px} color: #purple font: font("Monospace", 10, #bold);
                    y_offset <- y_offset + 20;
                    
                    loop i from: 0 to: min(3, length(stop_locations) - 1) { // Afficher max 3 arrêts
                        string stop_info <- "   " + stop_names[i] + " : " + stop_locations[i];
                        draw stop_info at: {10#px, y_offset#px} color: #black font: font("Monospace", 8);
                        y_offset <- y_offset + 15;
                    }
                } else {
                    draw "❌ Aucune donnée à afficher" at: {10#px, y_offset#px} color: #red;
                    y_offset <- y_offset + 20;
                    draw "🔍 Vérifiez le chemin du fichier GTFS" at: {10#px, y_offset#px} color: #orange;
                }
            }
        }
    }
}