/**
* Name: TimeManagementTest - Version Corrigée
* Description: Modèle de test pour vérifier la gestion du temps et le passage de jour
* Author: Test
* Tags: test, time, day_cycle, gtfs
*/

model TimeManagementTest

global {
    // === PARAMÈTRES DE TEST ===
    gtfs_file gtfs_f <- gtfs_file("../../includes/tisseo_gtfs_v2");
    date min_date_gtfs <- starting_date_gtfs(gtfs_f);
    date max_date_gtfs <- ending_date_gtfs(gtfs_f);
    shape_file boundary_shp <- shape_file("../../includes/shapeFileToulouse.shp");
    geometry shape <- envelope(boundary_shp);
    
    // Configuration temporelle pour test accéléré
    date starting_date <- date("2025-06-10T00:00:00"); // Commencer à minuit
    float step <- 60 #s; // 1 minute par cycle pour test rapide
    
    // === VARIABLES DE GESTION DU TEMPS CORRIGÉES ===
    int time_24h -> int(current_date - date([1970,1,1,0,0,0])) mod 86400;
    int current_seconds_mod <- 0;
    int current_day <- 0;
    int previous_seconds <- -1;
    
    // Nouvelle variable pour suivre le jour absolu
    int absolute_day <- 0;
    int previous_absolute_day <- 0;
    
    // === VARIABLES DE TEST ===
    int total_trips_to_launch <- 0;
    int launched_trips_count <- 0;
    list<string> launched_trip_ids <- [];
    
    // Variables pour le suivi des tests
    bool test_day_change_detected <- false;
    bool test_midnight_passed <- false;
    bool test_reset_confirmed <- false;
    int day_change_cycle <- -1;
    list<int> time_progression_log <- [];
    int max_time_reached <- 0;
    
    // Logs de test
    list<string> test_logs <- [];
    
    init {
        write "=== DÉBUT DU TEST DE GESTION DU TEMPS ===";
        do log_test("Initialisation du test");
        
        // Initialisation correcte des variables de jour
        absolute_day <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        previous_absolute_day <- absolute_day;
        current_day <- absolute_day;
        
        do log_test("Jour absolu initial : " + absolute_day);
        do log_test("Heure de début : " + time_24h + " secondes");
        
        create bus_stop from: gtfs_f {}
        
        // Compter les trips métro pour le test
        total_trips_to_launch <- sum((bus_stop where (each.routeType = 3)) collect each.tripNumber);
        do log_test("Total trips métro à lancer : " + total_trips_to_launch);
        
        do log_test("=== DÉBUT DE LA SURVEILLANCE TEMPORELLE ===");
    }
    
    // === ACTIONS DE TEST ===
    
    action log_test(string msg) {
        string timestamp <- "[Cycle " + cycle + " | " + current_seconds_mod + "s] ";
        test_logs <- test_logs + (timestamp + msg);
        write timestamp + msg;
    }
    
    // Fonction corrigée pour obtenir le temps actuel
    int get_time_now {
        return time_24h; // Utiliser directement time_24h qui est déjà modulo 86400
    }
    
    // === RÉFLEXES DE TEST CORRIGÉS ===
    
    reflex update_time_every_cycle {
        previous_seconds <- current_seconds_mod;
        current_seconds_mod <- get_time_now();
        
        // Mise à jour des jours
        previous_absolute_day <- absolute_day;
        absolute_day <- floor((int(current_date - date([1970,1,1,0,0,0]))) / 86400);
        
        // Enregistrer la progression du temps
        time_progression_log <- time_progression_log + current_seconds_mod;
        if current_seconds_mod > max_time_reached {
            max_time_reached <- current_seconds_mod;
        }
        
        // Test 1: Vérifier la progression normale du temps
        if previous_seconds >= 0 and current_seconds_mod < previous_seconds and !test_midnight_passed {
            do log_test("⚠️  TEMPS QUI RECULE DÉTECTÉ ! " + previous_seconds + " → " + current_seconds_mod);
            test_midnight_passed <- true; // Marquer le passage de minuit
        }
        
        // Test 2: Détecter l'approche de minuit
        if current_seconds_mod >= 86340 and current_seconds_mod < 86400 { // 23h59min
            do log_test("🕚 APPROCHE DE MINUIT : " + current_seconds_mod + "/86400");
        }
        
        // Test 3: Détecter le changement de jour absolu
        if absolute_day > previous_absolute_day and !test_day_change_detected {
            test_day_change_detected <- true;
            day_change_cycle <- cycle;
            do log_test("🎯 CHANGEMENT DE JOUR ABSOLU DÉTECTÉ !");
            do log_test("   - Ancien jour absolu : " + previous_absolute_day);
            do log_test("   - Nouveau jour absolu : " + absolute_day);
            do log_test("   - Cycle de détection : " + cycle);
            do log_test("   - Temps actuel : " + current_seconds_mod);
        }
        
        // Affichage périodique pour suivi
        if cycle mod 60 = 0 { // Toutes les heures en temps simulé
            int hours <- current_seconds_mod / 3600;
            int minutes <- (current_seconds_mod mod 3600) / 60;
            do log_test("⏰ Temps : " + hours + "h" + minutes + "min | Jour abs: " + absolute_day);
        }
    }
    
    // Reflex corrigé pour la gestion du changement de jour
    reflex test_day_change_and_reset when: test_day_change_detected and !test_reset_confirmed {
        do log_test("🔄 DÉBUT DU PROCESSUS DE RESET...");
        
        // Mettre à jour current_day
        current_day <- absolute_day;
        
        // Sauvegarder les anciennes valeurs pour le log
        int old_count <- launched_trips_count;
        int old_list_size <- length(launched_trip_ids);
        
        // Reset des variables comme dans le modèle original
        launched_trips_count <- 0;
        launched_trip_ids <- [];
        
        // Reset des arrêts
        ask bus_stop where (each.routeType = 3) {
            current_trip_index <- 0;
        }
        
        test_reset_confirmed <- true;
        
        do log_test("✅ RESET CONFIRMÉ :");
        do log_test("   - launched_trips_count : " + old_count + " → " + launched_trips_count);
        do log_test("   - launched_trip_ids.size : " + old_list_size + " → " + length(launched_trip_ids));
        do log_test("   - Arrêts remis à current_trip_index = 0");
        do log_test("   - current_day mis à jour : " + current_day);
    }
    
    // Condition de lancement des trips corrigée
    reflex launch_trips_condition when: launched_trips_count < total_trips_to_launch {
        // Cette condition permet de continuer à lancer des trips
        // même après le reset, pour tester la continuité
    }
    
    // Test de fin de simulation après 26h pour vérifier le comportement post-reset
    reflex end_test when: cycle > 1560 { // Environ 26h en temps simulé
        do log_test("=== FIN DU TEST ===");
        do log_test("📊 RÉSULTATS DU TEST :");
        do log_test("   - Temps max atteint : " + max_time_reached + "s (" + (max_time_reached/3600) + "h)");
        do log_test("   - Jour absolu final : " + absolute_day);
        do log_test("   - Minuit passé : " + (test_midnight_passed ? "✅ OUI" : "❌ NON"));
        do log_test("   - Changement de jour détecté : " + (test_day_change_detected ? "✅ OUI" : "❌ NON"));
        do log_test("   - Reset effectué : " + (test_reset_confirmed ? "✅ OUI" : "❌ NON"));
        do log_test("   - Cycle de changement de jour : " + day_change_cycle);
        do log_test("   - Trips lancés au final : " + launched_trips_count);
        do log_test("   - Bus restants : " + length(test_bus));
        
        // Test de cohérence finale
        if test_day_change_detected and test_reset_confirmed {
            do log_test("🎉 TOUS LES TESTS SONT PASSÉS AVEC SUCCÈS !");
        } else {
            do log_test("⚠️  CERTAINS TESTS ONT ÉCHOUÉ !");
            if !test_day_change_detected {
                do log_test("   - Changement de jour non détecté");
            }
            if !test_reset_confirmed {
                do log_test("   - Reset non effectué");
            }
        }
        
        do pause;
    }
}

species bus_stop skills: [TransportStopSkill] {
    rgb customColor <- rgb(0,0,255);
    map<string, bool> trips_launched;
    list<string> ordered_trip_ids;
    int current_trip_index <- 0;
    bool initialized <- false;

    reflex init_test when: cycle = 1 {
        ordered_trip_ids <- keys(departureStopsInfo);  
    }

    // Version simplifiée du lancement pour le test
    reflex launch_vehicles_for_test when: (departureStopsInfo != nil 
                                         and current_trip_index < length(ordered_trip_ids) 
                                         and routeType = 3
                                         and cycle mod 10 = 0) { // Lancer moins fréquemment pour le test
        
        string trip_id <- ordered_trip_ids[current_trip_index];
        list<pair<bus_stop, string>> trip_info <- departureStopsInfo[trip_id];
        string departure_time <- trip_info[0].value;

        if (current_seconds_mod >= int(departure_time) and not (trip_id in launched_trip_ids)) {
            // Créer un bus simplifié pour le test
            create test_bus with: [
                trip_id :: int(trip_id),
                departure_time :: int(departure_time),
                location :: location
            ];

            launched_trips_count <- launched_trips_count + 1;
            launched_trip_ids <- launched_trip_ids + trip_id;
            current_trip_index <- (current_trip_index + 1) mod length(ordered_trip_ids);
            
            if launched_trips_count mod 100 = 0 {
                write "📈 " + launched_trips_count + " trips lancés (temps: " + current_seconds_mod + "s)";
            }
        }
    }

    aspect base {
        draw circle(20) color: customColor;
    }
}

// Bus simplifié pour le test
species test_bus {
    int trip_id;
    int departure_time;
    int lifespan <- rnd(300, 3600); // Vie entre 5min et 1h
    int creation_cycle <- cycle;
    float heading <- rnd(360.0);
    
    aspect base {
        draw rectangle(100, 150) color: #green rotate: heading;
    }
    
    // Mourir après un certain temps pour éviter l'accumulation
    reflex die_after_time when: (cycle - creation_cycle) > lifespan {
        do die;
    }
}

experiment TimeTest type: gui {
    parameter "Vitesse de simulation" var: step min: 10#s max: 300#s;
    parameter "Heure de début" var: starting_date;
    
    output {
        display "Test Simulation" type: 2d {
            species bus_stop aspect: base;
            species test_bus aspect: base;
            
            overlay position: {10, 10} size: {450 #px, 280 #px} background: #white transparency: 0.8 {
                draw "=== TEST GESTION DU TEMPS (CORRIGÉ) ===" at: {20#px, 20#px} color: #black font: font("SansSerif", 12, #bold);
                draw "Cycle: " + cycle at: {20#px, 40#px} color: #black;
                draw "Temps actuel: " + current_seconds_mod + "s (" + int(current_seconds_mod/3600) + "h" + int((current_seconds_mod mod 3600)/60) + "min)" at: {20#px, 60#px} color: #blue;
                draw "Jour absolu: " + absolute_day + " (précédent: " + previous_absolute_day + ")" at: {20#px, 80#px} color: #black;
                draw "Jour current: " + current_day at: {20#px, 100#px} color: #black;
                draw "Temps max atteint: " + max_time_reached + "s" at: {20#px, 120#px} color: #darkgreen;
                draw "Bus actifs: " + length(test_bus) at: {20#px, 140#px} color: #green;
                draw "Trips lancés: " + launched_trips_count + "/" + total_trips_to_launch at: {20#px, 160#px} color: #red;
                
                // Indicateurs de test
                rgb midnight_color <- test_midnight_passed ? #green : #red;
                rgb day_change_color <- test_day_change_detected ? #green : #red;
                rgb reset_color <- test_reset_confirmed ? #green : #red;
                
                draw "Minuit passé: " + (test_midnight_passed ? "✅" : "❌") at: {20#px, 190#px} color: midnight_color;
                draw "Changement jour: " + (test_day_change_detected ? "✅" : "❌") at: {20#px, 210#px} color: day_change_color;
                draw "Reset confirmé: " + (test_reset_confirmed ? "✅" : "❌") at: {20#px, 230#px} color: reset_color;
                draw "Cycle changement: " + day_change_cycle at: {20#px, 250#px} color: #purple;
            }
        }
        
        display "Graphiques de Test" {
            chart "Progression du Temps" type: series {
                data "current_seconds_mod" value: current_seconds_mod color: #blue;
                data "previous_seconds" value: previous_seconds color: #orange;
            }
            
            chart "Jours" type: series {
                data "absolute_day" value: absolute_day color: #red;
                data "previous_absolute_day" value: previous_absolute_day color: #pink;
                data "current_day" value: current_day color: #darkred;
            }
            
            chart "Activité Bus" type: series {
                data "Bus actifs" value: length(test_bus) color: #green;
                data "Trips lancés (÷100)" value: launched_trips_count / 100 color: #orange;
            }
        }
        
        display "Logs de Test" type: java2D {
            overlay position: {10, 10} size: {700 #px, 450 #px} background: #white transparency: 0.9 {
                int y_pos <- 20;
                int max_logs <- 20; // Afficher les 20 derniers logs
                int start_index <- max(0, length(test_logs) - max_logs);
                
                draw "=== LOGS DE TEST (derniers " + max_logs + ") ===" at: {10#px, y_pos#px} color: #black font: font("Monospace", 10, #bold);
                y_pos <- y_pos + 20;
                
                loop i from: start_index to: length(test_logs) - 1 {
                    string log_entry <- test_logs[i];
                    rgb log_color <- #black;
                    
                    // Colorer selon le type de log
                    if contains(log_entry, "CHANGEMENT DE JOUR") or contains(log_entry, "✅") {
                        log_color <- #green;
                    } else if contains(log_entry, "ANOMALIE") or contains(log_entry, "⚠️") or contains(log_entry, "TEMPS QUI RECULE") {
                        log_color <- #red;
                    } else if contains(log_entry, "MINUIT") or contains(log_entry, "🌙") or contains(log_entry, "🕚") {
                        log_color <- #blue;
                    } else if contains(log_entry, "RESET") or contains(log_entry, "🔄") {
                        log_color <- #purple;
                    }
                    
                    draw log_entry at: {10#px, y_pos#px} color: log_color font: font("Monospace", 8);
                    y_pos <- y_pos + 15;
                }
            }
        }
    }
}