/**
 * Name: NoDuplicateAfterReload
 * Based on the internal empty template.
 * Author: tiend
 */

model NoDuplicateAfterReloadHanoi

global {
    // ------------ PARAMÈTRES ------------
    string gtfs_dir <- "../../includes/hanoi_gtfs_pm"; 

    // ------------ VARIABLES ------------
    gtfs_file gtfs_f;
    int phase <- 0; // 0 = premier run ; 1 = après reload
    int err_p0 <- 0; // erreurs phase 0
    int err_p1 <- 0; // erreurs phase 1
    
    // Compteurs pour monitoring
    int total_bus_stops_p0 <- 0;
    int total_transport_shapes_p0 <- 0;
    int total_bus_stops_p1 <- 0;
    int total_transport_shapes_p1 <- 0;

    // ------------ INIT : premier run ------------
    init {
        write "🚀 Test 2 — phase 0 (premier chargement)";
        gtfs_f <- gtfs_file(gtfs_dir);
        
        if gtfs_f = nil {
            write "❌ ERREUR : Impossible de charger le fichier GTFS depuis " + gtfs_dir;
            return;
        }
        
        do createEverything;
        write "📊 Phase 0 : " + string(length(bus_stop)) + " arrêts, " + string(length(transport_shape)) + " shapes créés";
    }

    // ------------ ACTION : création populations ------------
    action createEverything {
        create bus_stop from: gtfs_f;
        create transport_shape from: gtfs_f; // si shapes.txt absent, créateur « fake shapes »
    }

    // ------------ PHASE 0 : Vérification initiale ------------
    reflex verify_p0 when: phase = 0 and cycle = 2 {
        write "🔍 === VÉRIFICATION PHASE 0 ===";
        total_bus_stops_p0 <- length(bus_stop);
        total_transport_shapes_p0 <- length(transport_shape);

        err_p0 <- checkUniqueness();
        
        if err_p0 = 0 {
            write "✅ Phase 0 : Aucun doublon détecté lors du premier chargement";
        } else {
            write "❌ Phase 0 : " + string(err_p0) + " doublons détectés";
        }
        
        // Passage à la phase 1
        phase <- 1;

        write "♻️ RESET interne pour phase 1...";
        ask bus_stop { do die; }
        ask transport_shape { do die; }
        
        write "🔄 Rechargement des données...";
        do createEverything; // 2ᵉ création
        
        total_bus_stops_p1 <- length(bus_stop);
        total_transport_shapes_p1 <- length(transport_shape);
        write "📊 Phase 1 : " + string(total_bus_stops_p1) + " arrêts, " + string(total_transport_shapes_p1) + " shapes recréés";
    }

    // ------------ PHASE 1 : Vérification après rechargement ------------
    reflex verify_p1 when: phase = 1 and cycle = 4 {
        write "🔍 === VÉRIFICATION PHASE 1 ===";
        err_p1 <- checkUniqueness();
        
        if err_p1 = 0 {
            write "✅ Phase 1 : Aucun doublon détecté après rechargement";
        } else {
            write "❌ Phase 1 : " + string(err_p1) + " doublons détectés après rechargement";
        }

        // === BILAN FINAL ===
        write "📋 === BILAN FINAL DU TEST 2 ===";
        write "📊 Phase 0 : " + string(total_bus_stops_p0) + " arrêts, " + string(err_p0) + " erreurs";
        write "📊 Phase 1 : " + string(total_bus_stops_p1) + " arrêts, " + string(err_p1) + " erreurs";
        
        if err_p0 = 0 and err_p1 = 0 {
            write "🎉 TEST 2 RÉUSSI : aucun doublon, même après reload.";
        } else {
            write "🚨 TEST 2 ÉCHEC : doublons détectés.";
            if err_p0 > 0 {
                write "   - Phase 0 (initial) : " + string(err_p0) + " doublons";
            }
            if err_p1 > 0 {
                write "   - Phase 1 (reload) : " + string(err_p1) + " doublons";
            }
        }
    }

    // ------------ FONCTION commune : contrôle d'unicité ------------
    int checkUniqueness {
    int errors <- 0;
    write "🔍 Vérification de l'unicité des identifiants...";

    // ----- bus_stop -----
    if length(bus_stop) > 0 {
        list<string> stopIds <- bus_stop collect (each.stopId != nil ? string(each.stopId) : "nil");
        int total_stops <- length(stopIds);
        int unique_stops <- length(remove_duplicates(stopIds));
        int dupStops <- total_stops - unique_stops;

        if dupStops > 0 {
            write "❌ Doublons stopId : " + string(dupStops) + " sur " + string(total_stops);
            errors <- errors + dupStops;
            // Debug : afficher quelques doublons
            list<string> duplicates <- [];
            loop id over: remove_duplicates(stopIds) {
                int count <- stopIds count (each = id);
                if count > 1 {
                    duplicates <- duplicates + id;
                }
            }
            if length(duplicates) > 0 {
                write "   Exemples de stopIds dupliqués : " + string(first(duplicates, min(5, length(duplicates))));
            }
        } else {
            write "✅ Tous les stopId sont uniques (" + string(total_stops) + " arrêts)";
        }
    } else {
        write "⚠️ Aucun bus_stop trouvé";
    }

    // ----- transport_shape ----- (peut être vide si pas de shapes.txt)
    if length(transport_shape) > 0 {
        list<string> shapeIds <- transport_shape collect (each.shapeId != nil ? string(each.shapeId) : "nil");
        int total_shapes <- length(shapeIds);
        int unique_shapes <- length(remove_duplicates(shapeIds));
        int dupShapes <- total_shapes - unique_shapes;

        if dupShapes > 0 {
            write "❌ Doublons shapeId : " + string(dupShapes) + " sur " + string(total_shapes);
            errors <- errors + dupShapes;
        } else {
            write "✅ Tous les shapeId sont uniques (" + string(total_shapes) + " shapes)";
        }
    } else {
        write "ℹ️ Aucun transport_shape (shapes.txt absent) — check ignoré.";
    }

    // ----- tripId : vérifier les VRAIS doublons dans les arrêts de DÉPART -----
    if length(bus_stop) > 0 {
        // Collecter tous les tripId présents dans departureStopsInfo (arrêts de départ uniquement)
        map<string, int> tripId_depart_counts <- [];
        ask bus_stop {
            if (departureStopsInfo != nil and departureStopsInfo is map and length(departureStopsInfo) > 0) {
                loop tripId over: departureStopsInfo.keys {
                    if not(tripId_depart_counts contains_key tripId) {
                        tripId_depart_counts[tripId] <- 0;
                    }
                    tripId_depart_counts[tripId] <- tripId_depart_counts[tripId] + 1;
                }
            }
        }

        // Détecter les tripId présents dans plus d'un stop de départ (anormal !)
        list<string> true_trip_duplicates <- [];
        int dupTrips <- 0;
        loop tripId over: tripId_depart_counts.keys {
            if tripId_depart_counts[tripId] > 1 {
                true_trip_duplicates <- true_trip_duplicates + tripId;
                dupTrips <- dupTrips + (tripId_depart_counts[tripId] - 1);
            }
        }

        if length(true_trip_duplicates) > 0 {
            write "❌ TripId 'départ' dupliqué dans plusieurs bus_stop : " + string(true_trip_duplicates);
            write "   → Un trip ne peut avoir qu'UN SEUL arrêt de départ !";
            errors <- errors + dupTrips;
        } else {
            write "✅ Tous les tripId de départ sont uniques par bus_stop (" + string(length(tripId_depart_counts.keys)) + " trips de départ trouvés)";
        }
    }

    if errors = 0 {
        write "✅ AUCUN doublon détecté à cette phase.";
    } else {
        write "❌ TOTAL : " + string(errors) + " doublons détectés.";
    }
    
    return errors;
}
}

//— Espèces (skills existants) ——————————————————
species bus_stop skills: [TransportStopSkill] { 
    aspect base {
        draw circle(50) color: #blue border: #black;
    }
}

species transport_shape skills: [TransportShapeSkill] { 
    aspect base {
        if shape != nil {
            draw shape color: #red width: 2;
        }
    }
}

//— Expérience ——————————————————————
experiment NoDuplicateTest type: gui {
    parameter "Répertoire GTFS" var: gtfs_dir category: "Config";
    
    output {
        monitor "🔄 Phase" value: phase;
        monitor "❌ Erreurs phase 0" value: err_p0;
        monitor "❌ Erreurs phase 1" value: err_p1;
        monitor "🚏 Arrêts P0" value: total_bus_stops_p0;
        monitor "🚏 Arrêts P1" value: total_bus_stops_p1;
        monitor "🚌 Shapes P0" value: total_transport_shapes_p0;
        monitor "🚌 Shapes P1" value: total_transport_shapes_p1;
        monitor "📊 Cycle" value: cycle;
        
        display "Vue d'ensemble" {
            species bus_stop aspect: base;
            species transport_shape aspect: base;
            
            graphics "Info" {
                draw ("Test 2 - Phase " + string(phase)) at: {10, 10} 
                     color: #black font: font("Arial", 14, #bold);
                draw ("Cycle: " + string(cycle)) at: {10, 40} color: #gray;
                
                if phase = 0 {
                    draw "Phase 0: Chargement initial" at: {10, 70} color: #blue;
                } else {
                    draw "Phase 1: Après rechargement" at: {10, 70} color: #orange;
                }
            }
        }
    }
}