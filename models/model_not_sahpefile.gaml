/**
 * Name: PortNavigationSimulationOptimized
 * Description: Version optimisée avec mouvements linéaires des bateaux, meilleure gestion des collisions
 * et affichage du tableau uniquement dans la vue dédiée
 */
model PortNavigationSimulationOptimized

global {
    // Chargement des images
    file boat_img <- file_exists("../includes/boat.png") ? 
                    image_file("../includes/bateaux_vb.png") : 
                    image_file("bateaux_vb.png");
    
    file centre_control <- file_exists("../includes/centre.png") ? 
                             image_file("../includes/centre.png") : 
                             image_file("centre.png");
    
    // Définir la forme de la simulation
    geometry shape <- rectangle(1000, 600);
    
    // Point de transition eau/terre
    int coastline_x <- 600;
    
    // Définir l'espace d'eau - à gauche
    geometry waterArea <- rectangle(coastline_x, 600) at_location {coastline_x/2, 300};
    
    // Définir l'espace de terre - à droite
    geometry landArea <- rectangle(400, 600) at_location {coastline_x + 200, 300};
    
    // Points d'entrée et de sortie des bateaux
    point entryPoint <- {50, 150};
    point entryPoint2 <- {50, 300};
    point entryPoint3 <- {50, 450};
    point exitPoint <- {50, 300};
    
    // Capacité du port (nombre de points d'accostage)
    int portCapacity <- 5;
    
    // Points d'accostage (alignés le long de la côte)
    list<point> dockingPoints <- [];
    
    // Paramètres des bateaux
    float boatSize <- 2.0;
    float tonnageMin <- 5;
    float tonnageMax <- 60;
    
    // Durée d'accostage (6 minutes = 6 cycles dans la simulation)
    int dockingDuration <- 8;
    
    // Vitesses de déplacement
    float travelSpeedMin <- 2.0;
    float travelSpeedMax <- 5.0;
    
    // Vitesses de chargement/déchargement
    float loadingSpeedMin <- 1.0;
    float loadingSpeedMax <- 3.0;
    
    // Couleurs pour les catégories de bateaux
    rgb colorLarge <- rgb("green");
    rgb colorMedium <- rgb("blue");
    rgb colorSmall <- rgb("black");
    
    // Rayon de détection pour éviter les collisions
    float collision_avoidance_radius <- 30.0;
    
    // Statut de la marée
    string tideStatus <- "low";
    
    // Catégories de bateaux
    list<string> boatCategories <- ["small", "medium", "large"];
    
    // Distance minimale pour envoyer un signal du centre de contrôle
    float signal_distance <- 250.0;
    
    // Espacement vertical entre les bateaux (pour éviter les collisions)
    float vertical_spacing <- 40.0;
    
    init {
        // Calculer les points d'accostage régulièrement espacés le long de la côte
        float dock_spacing <- 500 / (portCapacity + 1);
        float y_start <- 50;
        
        loop i from: 0 to: portCapacity - 1 {
            dockingPoints <+ {coastline_x - 20, y_start + (i + 1) * dock_spacing};
        }
        
        // Créer la zone d'eau
        create water {
            shape <- waterArea;
        }
        
        // Créer la zone terrestre
        create land {
            shape <- landArea;
        }
        
        // Créer le centre de contrôle sur la terre
        create control_center {
            location <- {coastline_x + 150, 300};
        }
        
        // Créer les stations aux points d'accostage
        loop i from: 0 to: length(dockingPoints) - 1 {
            create docking_station {
                location <- dockingPoints[i];
                is_occupied <- false;
                station_id <- i + 1;
            }
        }
        
        // Création initiale des bateaux avec des positions verticales espacées
        create boat number: 5 {
            // Répartir les bateaux verticalement aux points d'entrée
            location <- {50, 100 + (length(boat) * vertical_spacing) mod 400};
            boatType <- one_of(boatCategories);
            
            // Définir les attributs selon le type de bateau
            if (boatType = "large") {
                size <- 40;
                color <- colorLarge;
                travelSpeed <- rnd(travelSpeedMin, travelSpeedMax - 1.0);
                tonnage <- rnd(45.0, tonnageMax);
                loadingSpeed <- rnd(loadingSpeedMin, 1.5);
            } else if (boatType = "medium") {
                size <- 30;
                color <- colorMedium;
                travelSpeed <- rnd(travelSpeedMin + 0.5, travelSpeedMax - 0.5);
                tonnage <- rnd(20.0, 45.0);
                loadingSpeed <- rnd(1.5, 2.5);
            } else if (boatType = "small") {
                size <- 20;
                color <- colorSmall;
                travelSpeed <- rnd(travelSpeedMax - 1.0, travelSpeedMax);
                tonnage <- rnd(tonnageMin, 20.0);
                loadingSpeed <- rnd(2.5, loadingSpeedMax);
            }
            
            // État initial: cherche un point d'accostage
            state <- "seeking_dock";
            target <- nil;
            boat_id <- length(boat);
            has_signal <- false;
            
            // Forcer une orientation vers la droite (côte)
            heading <- 90.0;
        }
    }
    
    // Reflex pour créer de nouveaux bateaux périodiquement
    reflex create_new_boats {
        if (length(boat) < 20 and flip(0.1)) {  // 10% de chance de créer un nouveau bateau à chaque cycle
            create boat {
                // Répartir les bateaux aux points d'entrée
                point entry <- one_of([entryPoint, entryPoint2, entryPoint3]);
                
                // Vérifier s'il y a déjà un bateau à cette position
                list<boat> nearby <- boat at_distance 30.0;
                if (!empty(nearby)) {
                    // Ajuster la position verticalement
                    entry <- {entry.x, entry.y + rnd(-50.0, 50.0)};
                }
                
                location <- entry;
                boatType <- one_of(boatCategories);
                
                if (boatType = "large") {
                    size <- 20;
                    color <- colorLarge;
                    travelSpeed <- rnd(travelSpeedMin, travelSpeedMax - 1.0);
                    tonnage <- rnd(45.0, tonnageMax);
                    loadingSpeed <- rnd(loadingSpeedMin, 1.5);
                } else if (boatType = "medium") {
                    size <- 15;
                    color <- colorMedium;
                    travelSpeed <- rnd(travelSpeedMin + 0.5, travelSpeedMax - 0.5);
                    tonnage <- rnd(20.0, 45.0);
                    loadingSpeed <- rnd(1.5, 2.5);
                } else if (boatType = "small") {
                    size <- 10;
                    color <- colorSmall;
                    travelSpeed <- rnd(travelSpeedMax - 1.0, travelSpeedMax);
                    tonnage <- rnd(tonnageMin, 20.0);
                    loadingSpeed <- rnd(2.5, loadingSpeedMax);
                }
                
                state <- "seeking_dock";
                target <- nil;
                boat_id <- length(boat);
                has_signal <- false;
                
                // Forcer une orientation vers la droite (côte)
                heading <- 90.0;
            }
        }
    }
    
    // Reflex pour compter les bateaux à chaque cycle
    reflex debug_counts {
        write "Nombre actuel de bateaux: " + length(boat);
    }
}

// Représentation de l'eau
species water {
    aspect default {
        draw shape color: #lightblue;
    }
}

// Représentation de la terre
species land {
    aspect default {
        draw shape color: #gray;
    }
}

// Représentation du centre de contrôle
species control_center {
    // Attributs du centre de contrôle
    float signal_radius <- signal_distance;  // Rayon de détection pour envoyer des signaux
    int max_signals_per_cycle <- 3;  // Nombre maximum de signaux par cycle (optionnel)
    bool is_active <- true;  // État du centre de contrôle
    
    // Reflex pour assigner les stations aux bateaux qui cherchent à accoster
    reflex assign_docking_stations when: is_active {
        // Trouver les bateaux qui cherchent une place
        list<boat> seeking_boats <- boat where (each.state = "seeking_dock" and each.target = nil);
        
        if (!empty(seeking_boats)) {
            // Trier les bateaux par proximité à la côte (ceux qui sont plus proches d'abord)
            seeking_boats <- seeking_boats sort_by (each distance_to self);
            
            // Trouver les stations disponibles
            list<docking_station> available_stations <- docking_station where (!each.is_occupied and each.assigned_boat = nil);
            
            if (!empty(available_stations)) {
                // Assigner la station au premier bateau de la liste
                boat selected_boat <- seeking_boats[0];
                
                // Trouver la station la plus proche de la position Y du bateau
                docking_station best_station <- nil;
                float min_distance <- #max_float;
                
                loop station over: available_stations {
                    float dist <- abs(station.location.y - selected_boat.location.y);
                    if (dist < min_distance) {
                        min_distance <- dist;
                        best_station <- station;
                    }
                }
                
                // Assigner la station
                selected_boat.target <- best_station;
                best_station.assigned_boat <- selected_boat;
                
                // Calculer un chemin direct
                ask selected_boat {
                    do calculate_path;
                }
            }
        }
    }
    
    // Reflex pour envoyer des signaux aux bateaux qui approchent des stations
    reflex send_signals when: is_active {
        int signals_sent <- 0;
        ask boat where (each.state = "seeking_dock" and each.target != nil and !each.has_signal) {
            if (self distance_to myself < myself.signal_radius) {
                self.has_signal <- true;
                write "Le centre de contrôle envoie un signal au bateau " + self.boat_id + " pour l'accostage à la station " + self.target.station_id;
                signals_sent <- signals_sent + 1;
                
                // Limiter le nombre de signaux par cycle (optionnel)
                if (signals_sent >= myself.max_signals_per_cycle) {
                    break;
                }
            }
        }
    }
    
    aspect default {
        draw centre_control size: 300;
        
        // Visualiser le rayon de signalisation
        draw circle(signal_radius) color: #yellow border: #orange empty: true;
    }
}

// Représentation des stations d'accostage
species docking_station {
    bool is_occupied <- false;
    int station_id;
    boat assigned_boat <- nil;
    
    aspect default {
        // Rouge quand libre, jaune quand occupé
        draw square(35) color: is_occupied ? #yellow : #red border: #black;
        draw string(station_id) size: 12 color: #black at: location + {0, -20};
    }
}

// Représentation des bateaux
species boat skills: [moving] {
    string boatType;
    float travelSpeed;
    int size;
    rgb color;
    float tonnage;
    float loadingSpeed;
    int boat_id;
    
    // États possibles: seeking_dock, docked, returning
    string state;
    docking_station target;
    int docking_time <- 0;
    bool has_signal <- false;
    
    // Liste des points de chemin
    list<point> path_points <- [];
    
    // Calculer un chemin direct vers la station assignée
    action calculate_path {
        path_points <- [];
        
        if (target != nil) {
            // Point de départ: position actuelle
            point start <- location;
            
            // Créer un point intermédiaire pour garantir un déplacement horizontal d'abord
            point waypoint <- {target.location.x - 100, location.y};
            
            // Puis un second point pour le déplacement vertical final
            point final_approach <- {target.location.x - 100, target.location.y};
            
            // Ajout des points au chemin
            path_points <+ start;
            path_points <+ waypoint;
            path_points <+ final_approach;
            path_points <+ target.location;
        }
    }
    
    aspect default {
        draw circle(size) color: color rotate:90;
        
        // Montrer la direction avec une petite ligne
        point dest <- {location.x + 15, location.y};
        draw line([location, dest]) color: #black;
        
        draw string(boat_id) size: 10 color: #white at: location + {0, -15};
    }
    
    aspect icon {
        // Dessiner le bateau orienté vers la droite
        if (file_exists(boat_img.path)) {
            draw boat_img size: size * 2 ;
        } else {
            draw triangle(size) color: color ;
        }
        
        // Afficher le signal reçu
        if (has_signal and state = "seeking_dock") {
            draw circle(size * 1.5) color: #yellow empty: true;
        }
        
        // Afficher l'ID du bateau
        draw string(boat_id) size: 10 color: #black at: location + {0, -size * 1.2};
    }
    
    // Chercher un point d'accostage disponible
    reflex seek_docking_point when: state = "seeking_dock" {
        if (target != nil) {
            // Si on a des points de chemin, les suivre
            if (!empty(path_points)) {
                point nextPoint <- path_points[0];
                do goto target: nextPoint speed: travelSpeed;
                
                // Forcer l'orientation vers la droite
                heading <- 90.0;
                
                // Si le point est atteint, passer au suivant
                if (location distance_to nextPoint < 5) {
                    path_points <- path_points - nextPoint;
                    
                    // Si on a atteint le dernier point (la station)
                    if (empty(path_points)) {
                        target.is_occupied <- true;
                        state <- "docked";
                        docking_time <- 0;
                    }
                }
            } else {
                // Si pas de points de chemin, aller directement à la station
                do goto target: target.location speed: travelSpeed;
                
                // Forcer l'orientation vers la droite
                heading <- 90.0;
                
                // Vérifier si le bateau est arrivé à destination
                if (location distance_to target.location < 5) {
                    target.is_occupied <- true;
                    state <- "docked";
                    docking_time <- 0;
                }
            }
        } else {
            // Si aucune station n'est assignée, avancer lentement vers la droite
            location <- location + {travelSpeed * 0.5, 0};
            
            // Rester dans les limites de l'eau
            if (location.x > coastline_x - 150) {
                location <- {coastline_x - 150, location.y};
            }
        }
    }
    
    // Éviter les collisions avec d'autres bateaux
    reflex avoid_collisions when: state = "seeking_dock" or state = "returning" {
        list<boat> nearby_boats <- (boat at_distance collision_avoidance_radius) - self;
        
        if (!empty(nearby_boats)) {
            point avoid_force <- {0, 0};
            
            loop other_boat over: nearby_boats {
                // Calculer seulement la composante verticale de l'évitement
                // pour maintenir le déplacement horizontal
                float y_diff <- location.y - other_boat.location.y;
                float distance <- self distance_to other_boat;
                float factor <- 1 - (distance / collision_avoidance_radius);
                
                // Créer une force qui pousse seulement verticalement
                avoid_force <- avoid_force + {0, y_diff * factor};
            }
            
            // Appliquer une petite déviation verticale pour éviter la collision
            if (norm(avoid_force) > 0) {
                location <- location + {0, min(2.0, avoid_force.y * 0.1)};
            }
        }
    }
    
    // Rester accosté pendant la durée spécifiée
    reflex stay_at_dock when: state = "docked" {
        docking_time <- docking_time + 1;
        
        // Calculer le temps d'accostage en fonction de la vitesse de chargement/déchargement
        int adjusted_docking_time <- int(dockingDuration / loadingSpeed * 2);
        
        // Si le temps d'accostage est terminé, partir
        if (docking_time >= adjusted_docking_time) {
            state <- "returning";
            target.is_occupied <- false;  // Libérer la station
            target.assigned_boat <- nil;  // Désassigner le bateau
            target <- nil;
            has_signal <- false;          // Réinitialiser le signal
        }
    }
    
    // Retourner au point de sortie
    reflex return_to_exit when: state = "returning" {
        // Se déplacer vers la gauche (vers le point de sortie)
        location <- location + {-travelSpeed, 0};
        
        // Si le bateau atteint le bord gauche, le supprimer
        if (location.x < 10) {
            do die;
        }
    }
}

// Définition de l'expérience
experiment port_navigation_simulation type: gui {
    parameter "Niveau de Marée" category: "Niveau d'Eau" var: tideStatus <- "low" among: ["low", "high"];
    
    output {
        display port_view type: java2D {
            // Affichage du fond
            species water;
            species land;
            species docking_station;
            species control_center;
            species boat aspect: icon;
            
            graphics "Info" {
                draw "Port Navigation Simulation - Goma" at: {10, 30} color: #black font: font('Default', 18, #bold);
                draw "Niveau de Marée: " + tideStatus at: {10, 60} color: #black font: font('Default', 14, #bold);
            }
        }
        
		// Vue dédiée pour les graphiques et statistiques
		display information_simulation refresh: every(5#cycles) {
		    chart "Average Transit Time" type: series background: #white axes: #black {
		        data "Average Transit Time" value: mean(boat collect each.travelSpeed) color: #blue marker: true;
		    }
		}
		
		display boat_stats_distribution refresh: every(5#cycles) {
		    chart "Boating activities" type: pie background: #white {
		        data "Boats approaching the dock" value: length(boat where (each.state = "seeking_dock")) color: #orange;
		        data "Boats leaving after docking" value: length(boat where (each.state = "docked")) color: #green;
		        data "Boats in docking" value: length(boat where (each.state = "returning")) color: #cyan;
		    }
		}

    }
}