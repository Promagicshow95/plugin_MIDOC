

model AttributeInjection

global {
    // --- PARAMÈTRES ---
    string gtfs_dir <- "../../includes/hanoi_gtfs_pm"; 

    // --- VARIABLES GLOBALES ---
    gtfs_file gtfs_f;
    int errors_total <- 0;
    int total_bus_stops <- 0;
    int total_transport_shapes <- 0;
    
    // --- INITIALISATION ---
    init {
        write "🚀 Début du test 1 - Injection et typage des attributs ";
        write "📂 Chargement du GTFS depuis : " + gtfs_dir;
        
        // Chargement du fichier GTFS
        gtfs_f <- gtfs_file(gtfs_dir);
        
        if gtfs_f = nil {
            write "❌ ERREUR CRITIQUE : Impossible de charger le fichier GTFS !";
            do die;
        }
        
        // Création des agents bus_stop
        write "🚏 Création des arrêts de bus...";
        create bus_stop from: gtfs_f;
        total_bus_stops <- length(bus_stop);
        write "✅ " + string(total_bus_stops) + " arrêts créés";
        
        // Création des agents transport_shape
        write "🚌 Création des formes de transport...";
        create transport_shape from: gtfs_f;
        total_transport_shapes <- length(transport_shape);
        write "✅ " + string(total_transport_shapes) + " formes créées";
        
        write "📊 Initialisation terminée. Test des attributs au prochain cycle...";
    }

    // --- FONCTION UTILITAIRE : Test de type flexible ---
    bool test_attribute_type(string agent_type, string agent_id, unknown attr_value, string attr_name, string expected_type) {
        if (attr_value = nil) {
            write "❌ " + agent_type + " " + agent_id + " : " + attr_name + " manquant";
            errors_total <- errors_total + 1;
            return false;
        }
        
        string actual_type <- string(type_of(attr_value));
        
        // Test de type selon les règles spécifiques
        bool type_ok <- false;
        
        if (expected_type = "flexible_id") {
            // Accepter string, int, ou unknown pour les IDs
            type_ok <- (actual_type = "string") or (actual_type = "int") or (actual_type = "unknown");
        } else if (expected_type = "flexible_map") {
            // Accepter tout type de map
            type_ok <- contains(actual_type, "map");
        } else if (expected_type = "geometry") {
            type_ok <- (actual_type = "geometry") or contains(actual_type, "geometry");
        } else {
            type_ok <- (actual_type = expected_type);
        }
        
        if not type_ok {
            write "❌ " + agent_type + " " + agent_id + " : " + attr_name + " mauvais type (" + actual_type + ", attendu: " + expected_type + ")";
            errors_total <- errors_total + 1;
            return false;
        }
        
        return true;
    }

    // --- REFLEXE DE TEST : se déclenche au 2ᵉ cycle (après instanciation) ---
    reflex check_attributes when: cycle = 2 {
        write "🔍 === DÉBUT DU TEST DES ATTRIBUTS (VERSION CORRIGÉE) ===";
        errors_total <- 0;

        /* =========================================
         * 1. BUS_STOP : présence & typage avec types réels
         * ========================================= */
        write "🚏 Test des attributs bus_stop...";
        ask bus_stop {
            string current_stop_id <- (stopId != nil) ? string(stopId) : "ID_INCONNU";
            string agent_id <- string(index);
            
            // Test de tous les attributs avec types flexibles
            bool test1 <- myself.test_attribute_type("bus_stop", agent_id, stopId, "stopId", "flexible_id");
            bool test2 <- myself.test_attribute_type("bus_stop", agent_id, stopName, "stopName", "string");
            bool test3 <- myself.test_attribute_type("bus_stop", agent_id, routeType, "routeType", "int");
            bool test4 <- myself.test_attribute_type("bus_stop", agent_id, tripShapeMap, "tripShapeMap", "flexible_map");
            bool test5 <- myself.test_attribute_type("bus_stop", agent_id, departureStopsInfo, "departureStopsInfo", "flexible_map");
            
            // DIAGNOSTIC AVANCÉ : Examiner la structure réelle des maps
            if (tripShapeMap != nil and cycle = 2 and index < 3) {
                write "🔍 DEBUG tripShapeMap pour " + current_stop_id + ":";
                write "   Type réel: " + string(type_of(tripShapeMap));
                write "   Taille: " + string(length(tripShapeMap));
                if (length(tripShapeMap) > 0) {
                    list keys_list <- tripShapeMap.keys;
                    if (length(keys_list) > 0) {
                        string first_key <- string(keys_list[0]);
                        string first_value <- string(tripShapeMap[keys_list[0]]);
                        string first_key_type <- string(type_of(keys_list[0]));
                        string first_value_type <- string(type_of(tripShapeMap[keys_list[0]]));
                        write "   Exemple - Clé: " + first_key + " (type: " + first_key_type + ") → Valeur: " + first_value + " (type: " + first_value_type + ")";
                    }
                }
            }
            
            if (departureStopsInfo != nil and cycle = 2 and index < 3) {
                write "🔍 DEBUG departureStopsInfo pour " + current_stop_id + ":";
                write "   Type réel: " + string(type_of(departureStopsInfo));
                write "   Taille: " + string(length(departureStopsInfo));
                if (length(departureStopsInfo) > 0) {
                    list keys_list <- departureStopsInfo.keys;
                    if (length(keys_list) > 0) {
                        string first_key <- string(keys_list[0]);
                        string first_value_type <- string(type_of(departureStopsInfo[keys_list[0]]));
                        write "   Exemple - Clé: " + first_key + " → Valeur type: " + first_value_type;
                    }
                }
            }
        }

        /* =========================================
         * 2. TRANSPORT_SHAPE : présence & typage avec types réels
         * ========================================= */
        write "🚌 Test des attributs transport_shape...";
        ask transport_shape {
            string current_shape_id <- (shapeId != nil) ? string(shapeId) : "SHAPE_ID_INCONNU";
            string agent_id <- string(index);
            
            // Test de tous les attributs
            bool test1 <- myself.test_attribute_type("transport_shape", agent_id, shapeId, "shapeId", "flexible_id");
            bool test2 <- myself.test_attribute_type("transport_shape", agent_id, shape, "shape", "geometry");
            bool test3 <- myself.test_attribute_type("transport_shape", agent_id, routeType, "routeType", "int");
            bool test4 <- myself.test_attribute_type("transport_shape", agent_id, routeId, "routeId", "string");
            
            // DIAGNOSTIC pour les premiers shapes
            if (cycle = 2 and index < 3) {
                write "🔍 DEBUG transport_shape " + current_shape_id + ":";
                if (shapeId != nil) {
                    write "   shapeId: " + string(shapeId) + " (type: " + string(type_of(shapeId)) + ")";
                }
                if (shape != nil) {
                    write "   shape type: " + string(type_of(shape));
                }
                if (routeType != nil) {
                    write "   routeType: " + string(routeType) + " (type: " + string(type_of(routeType)) + ")";
                }
                if (routeId != nil) {
                    write "   routeId: " + string(routeId) + " (type: " + string(type_of(routeId)) + ")";
                }
            }
        }

        /* =========================================
         * 3. ANALYSE DES TYPES TROUVÉS
         * ========================================= */
        write "📋 === ANALYSE DES TYPES RÉELS ===";
        
        // Compter les types uniques pour chaque attribut
        map<string, int> types_stopId <- [];
        map<string, int> types_tripShapeMap <- [];
        map<string, int> types_departureStopsInfo <- [];
        
        ask bus_stop {
            if (stopId != nil) {
                string t <- string(type_of(stopId));
                if not(types_stopId contains_key t) { 
                    types_stopId[t] <- 0; 
                }
                types_stopId[t] <- types_stopId[t] + 1;
            }
            
            if (tripShapeMap != nil) {
                string t <- string(type_of(tripShapeMap));
                if not(types_tripShapeMap contains_key t) { 
                    types_tripShapeMap[t] <- 0; 
                }
                types_tripShapeMap[t] <- types_tripShapeMap[t] + 1;
            }
            
            if (departureStopsInfo != nil) {
                string t <- string(type_of(departureStopsInfo));
                if not(types_departureStopsInfo contains_key t) { 
                    types_departureStopsInfo[t] <- 0; 
                }
                types_departureStopsInfo[t] <- types_departureStopsInfo[t] + 1;
            }
        }
        
        write "🔍 Types réels trouvés dans bus_stop:";
        write "   stopId: " + string(types_stopId);
        write "   tripShapeMap: " + string(types_tripShapeMap);
        write "   departureStopsInfo: " + string(types_departureStopsInfo);

        /* =========================================
         * 4. BILAN DU TEST
         * ========================================= */
        write "📊 === BILAN DU TEST ===";
        write "🚏 Arrêts testés : " + string(total_bus_stops);
        write "🚌 Shapes testées : " + string(total_transport_shapes);
        
        if (errors_total = 0) {
            write "✅ TEST RÉUSSI : tous les attributs sont présents et correctement typés.";
        } else {
            write "❌ TEST ÉCHEC : " + string(errors_total) + " problème(s) détecté(s).";
        }

        // Recommandations
        if (errors_total > 0) {
            write "💡 RECOMMANDATIONS:";
            write "   1. Vérifier que le plugin GTFS est à jour";
            write "   2. Contrôler la qualité des fichiers GTFS source";
            write "   3. Adapter les déclarations de types dans les species";
            write "⏹️  Test terminé avec des erreurs.";
        } else {
            write "🎉 Test terminé avec succès !";
        }
    }
}

// === SPECIES BUS_STOP (sans déclaration de types spécifiques) ===
species bus_stop skills: [TransportStopSkill] {
    // Laisser le plugin GTFS injecter les attributs avec leurs types natifs
    // Les attributs seront : stopId, stopName, routeType, tripShapeMap, departureStopsInfo
}

// === SPECIES TRANSPORT_SHAPE (sans déclaration de types spécifiques) ===
species transport_shape skills: [TransportShapeSkill] {
    // Laisser le plugin GTFS injecter les attributs avec leurs types natifs  
    // Les attributs seront : shapeId, shape, routeType, routeId
}

// === EXPÉRIENCE ===
experiment AttributeInjectionTest type: gui {
    parameter "Répertoire GTFS" var: gtfs_dir category: "Configuration";
    
    output {
        monitor "💡 Total erreurs attributs" value: errors_total;
        monitor "🚏 Arrêts créés" value: total_bus_stops;
        monitor "🚌 Shapes créées" value: total_transport_shapes;
        monitor "📊 Cycle actuel" value: cycle;
        
        display "Résumé du Test" {
            graphics "Info" {
                draw "Test - Injection des Attributs (CORRIGÉ)" at: {10, 10} 
                     color: #black font: font("Arial", 14, #bold);
                draw ("Erreurs détectées : " + string(errors_total)) at: {10, 40} 
                     color: (errors_total = 0 ? #green : #red) font: font("Arial", 12);
                draw ("Arrêts : " + string(total_bus_stops)) at: {10, 70} color: #blue;
                draw ("Shapes : " + string(total_transport_shapes)) at: {10, 100} color: #purple;
            }
        }
    }
}