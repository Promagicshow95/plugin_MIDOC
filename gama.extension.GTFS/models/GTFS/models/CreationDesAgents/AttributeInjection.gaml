/*
 * Test T-3.9-02 & 03 – Injection et typage des attributs
 * ------------------------------------------------------
 * Vérifie pour chaque agent :
 * – présence de tous les attributs requis
 * – absence de nil
 * – conformité du type (string, int, map, polyline…)
 *
 * AUTEUR : (votre nom)
 * DATE : 2025-07-02
 */

model T_3_9_02_AttributeInjection

global {
    // --- PARAMÈTRES ---
    string gtfs_dir <- "../../includes/nantes_gtfs"; // ⇦ ajustez si besoin

    // --- VARIABLES GLOBALES ---
    gtfs_file gtfs_f;
    int errors_total <- 0;
    int total_bus_stops <- 0;
    int total_transport_shapes <- 0;
    
    // --- INITIALISATION ---
    init {
        write "🚀 Début du test 1 - Injection et typage des attributs";
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

    // --- REFLEXE DE TEST : se déclenche au 2ᵉ cycle (après instanciation) ---
    reflex check_attributes when: cycle = 2 {
        write "🔍 === DÉBUT DU TEST DES ATTRIBUTS ===";
        errors_total <- 0;

        /* =========================================
         * 1. BUS_STOP : présence & typage
         * ========================================= */
        write "🚏 Test des attributs bus_stop...";
        ask bus_stop {
            string current_stop_id <- (stopId != nil) ? string(stopId) : "ID_INCONNU";
            
            // ---- stopId : string ou int accepté
            if (stopId = nil) {
                write "❌ bus_stop [index:" + string(index) + "] : stopId manquant";
                myself.errors_total <- myself.errors_total + 1;
            }
            
            // ---- stopName : string
            if (stopName = nil) {
                write "❌ bus_stop " + current_stop_id + " : stopName manquant";
                myself.errors_total <- myself.errors_total + 1;
            } else if (!(type_of(stopName) = string)) {
                write "❌ bus_stop " + current_stop_id + " : stopName mauvais type (" + string(type_of(stopName)) + ")";
                myself.errors_total <- myself.errors_total + 1;
            }

            // ---- routeType : int
            if (routeType = nil) {
                write "❌ bus_stop " + current_stop_id + " : routeType manquant";
                myself.errors_total <- myself.errors_total + 1;
            } else if (!(type_of(routeType) = int)) {
                write "❌ bus_stop " + current_stop_id + " : routeType mauvais type (" + string(type_of(routeType)) + ")";
                myself.errors_total <- myself.errors_total + 1;
            }

            // ---- tripShapeMap : map
            if (tripShapeMap = nil) {
                write "❌ bus_stop " + current_stop_id + " : tripShapeMap manquant";
                myself.errors_total <- myself.errors_total + 1;
            } else if (!(type_of(tripShapeMap) = map)) {
                write "❌ bus_stop " + current_stop_id + " : tripShapeMap mauvais type (" + string(type_of(tripShapeMap)) + ")";
                myself.errors_total <- myself.errors_total + 1;
            }

            // ---- departureStopsInfo : map
            if (departureStopsInfo = nil) {
                write "❌ bus_stop " + current_stop_id + " : departureStopsInfo manquant";
                myself.errors_total <- myself.errors_total + 1;
            } else if (!(type_of(departureStopsInfo) = map)) {
                write "❌ bus_stop " + current_stop_id + " : departureStopsInfo mauvais type (" + string(type_of(departureStopsInfo)) + ")";
                myself.errors_total <- myself.errors_total + 1;
            }
        }

        /* =========================================
         * 2. TRANSPORT_SHAPE : présence & typage
         * ========================================= */
        write "🚌 Test des attributs transport_shape...";
        ask transport_shape {
            string current_shape_id <- (shapeId != nil) ? string(shapeId) : "SHAPE_ID_INCONNU";
            
            // ---- shapeId : string ou int accepté
            if (shapeId = nil) {
                write "❌ transport_shape [index:" + string(index) + "] : shapeId manquant";
                myself.errors_total <- myself.errors_total + 1;
            }

            // ---- shape : geometry (polyline)
            if (shape = nil) {
                write "❌ transport_shape " + current_shape_id + " : shape (polyline) manquante";
                myself.errors_total <- myself.errors_total + 1;
            } else if (!(type_of(shape) = geometry)) {
                write "❌ transport_shape " + current_shape_id + " : shape mauvais type (" + string(type_of(shape)) + ")";
                myself.errors_total <- myself.errors_total + 1;
            }

            // ---- routeType : int
            if (routeType = nil) {
                write "❌ transport_shape " + current_shape_id + " : routeType manquant";
                myself.errors_total <- myself.errors_total + 1;
            } else if (!(type_of(routeType) = int)) {
                write "❌ transport_shape " + current_shape_id + " : routeType mauvais type (" + string(type_of(routeType)) + ")";
                myself.errors_total <- myself.errors_total + 1;
            }

            // ---- routeId : string
            if (routeId = nil) {
                write "❌ transport_shape " + current_shape_id + " : routeId manquant";
                myself.errors_total <- myself.errors_total + 1;
            } else if (!(type_of(routeId) = string)) {
                write "❌ transport_shape " + current_shape_id + " : routeId mauvais type (" + string(type_of(routeId)) + ")";
                myself.errors_total <- myself.errors_total + 1;
            }
        }

        /* =========================================
         * 3. BILAN DU TEST
         * ========================================= */
        write "📊 === BILAN DU TEST ===";
        write "🚏 Arrêts testés : " + string(total_bus_stops);
        write "🚌 Shapes testées : " + string(total_transport_shapes);
        
        if (errors_total = 0) {
            write "✅ T-3.9-02/03 RÉUSSI : aucun attribut manquant ni mauvais typage.";
        } else {
            write "❌ T-3.9-02/03 ÉCHEC : " + string(errors_total) + " problème(s) détecté(s).";
        }

        // Optionnel : arrêter la simu en cas d'échec
        if errors_total > 0 {
            write "⏹️  Test terminé avec des erreurs.";
        } else {
            write "🎉 Test terminé avec succès !";
        }
    }
}

// === SPECIES BUS_STOP ===
species bus_stop skills: [TransportStopSkill] {
}

// === SPECIES TRANSPORT_SHAPE ===
species transport_shape skills: [TransportShapeSkill] {
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
                draw "Test - Injection des Attributs" at: {10, 10} 
                     color: #black font: font("Arial", 14, #bold);
                draw ("Erreurs détectées : " + string(errors_total)) at: {10, 40} 
                     color: (errors_total = 0 ? #green : #red) font: font("Arial", 12);
                draw ("Arrêts : " + string(total_bus_stops)) at: {10, 70} color: #blue;
                draw ("Shapes : " + string(total_transport_shapes)) at: {10, 100} color: #purple;
            }
        }
    }
}