/**
* Simulation du système de navigation portuaire
* Description: Simulation de la gestion des bateaux dans un port avec considération des marées
*/

model port_navigation

// Définition de la grille de navigation
grid nav_cell width: 50 height: 50 {
    rgb color <- #blue;
    bool is_obstacle <- false;
    bool is_entrance <- false;
    bool is_path <- false;
}

global {
    // Variables globales
    int nb_parking_spaces <- 5;                    // Nombre d'espaces de stationnement
    float current_tide_level <- 5.0;               // Niveau actuel de la marée (mètres)
    float max_tide_level <- 10.0;                  // Niveau maximum de la marée
    float min_tide_level <- 0.0;                   // Niveau minimum de la marée
    float tide_change_rate <- 0.1;                 // Taux de changement de la marée
    geometry water_area;
    point port_exit <- {0,0};  // Sera initialisé dans init
    point port_entrance <- {25, 45};               // Point d'entrée du port
    list<point> navigation_points;                 // Points de navigation pour les bateaux
    
    // Nouveaux paramètres des shapefiles
    file port_shape_file <- shape_file("../includes/goma_port.shp");
    file space_station_shape_file <- shape_file("../includes/d_stations.shp");
    file centre_control_shape_file <- shape_file("../includes/goma_centre_c.shp");
    file water_shape_file <- shape_file("../includes/goma_water.shp");
    file boat_image <- image_file("../includes/boat.png");
    
    // Paramètres de simulation
    int number_of_boats <- 1;
    int simulation_duration <- 120;
    
    // Définition de l'espace
    geometry shape <- envelope(port_shape_file) + envelope(water_shape_file) + 
                     envelope(centre_control_shape_file) + envelope(space_station_shape_file);
    
    // Statistiques
    int total_boats_serviced <- 0;
    float total_cargo_exchanged <- 0.0;
    list<Boat> waiting_queue <- [];
    
    // Initialisation de la simulation
    init {
        create Water_Body from: water_shape_file;
        water_area <- first(Water_Body).shape;
        port_exit <- any_location_in(water_area);  // Point de sortie dans l'eau
        
        create Control_Center from: centre_control_shape_file;
        
        create Parking_Space from: space_station_shape_file with: [
            depth::float(get("depth"))
        ];
        
        create Boat number: number_of_boats {
            location <- any_point_in(water_area);
            initial_location <- copy(location);
            target <- any_point_in(water_area);  // Point d'entrée aléatoire dans l'eau
            write "Bateau " + name + " créé à " + location + " - Statut: chargé";
        }
    }
    
    // Configuration des chemins de navigation
    action setup_navigation_paths {
        navigation_points <- [{25,45}, {25,35}, {25,25}, {15,15}];
        ask nav_cell {
            if (grid_x = 25 and grid_y > 15) {
                is_path <- true;
                color <- rgb(200, 200, 255);
            }
        }
    }
    
    // Mise à jour du niveau de marée
    reflex update_tide {
        current_tide_level <- min_tide_level + (max_tide_level - min_tide_level) * (1 + sin(cycle * tide_change_rate)) / 2;
    }
    
    // Action pour trouver un point de sortie valide
    action find_exit_point(point current_location) type: point {
        // Le point de sortie sera à x=0 et légèrement au-dessus de la position actuelle
        float target_y <- current_location.y - 1;
        
        // S'assurer que le y reste dans les limites de la zone d'eau
        float min_y <- water_area.points min_of each.y;
        if (target_y < min_y) { target_y <- min_y; }
        
        // Créer le point de sortie
        point exit_point <- {0, target_y};
        
        // Vérifier si le point est dans l'eau
        if (exit_point intersects water_area) {
            return exit_point;
        } else {
            // Si le point n'est pas dans l'eau, retourner le point le plus proche sur le bord gauche
            list<point> border_points <- water_area.points where (each.x = (water_area.points min_of each.x));
            return border_points closest_to current_location;
        }
    }
    
    // Création occasionnelle de nouveaux bateaux
    reflex create_random_boat when: flip(0.05) {  // 5% de chance chaque cycle
        create Boat {
            location <- {0.0,0.011269871392754195,0.0};
            initial_location <- copy(location);
            target <- any_point_in(water_area);
            write "Nouveau bateau " + name + " créé à " + location + " - Statut: chargé";
        }
    }
}

species Water_Body {
    float tide_level <- 5.0;
    
    aspect default {
        draw shape color: rgb(65, 105, 225, 120);
    }
}

// Définition des bateaux
species Boat skills: [moving] control: fsm {
    float tonnage <- rnd(100.0, 1000.0);
    float speed <- rnd(0.0002, 0.0005);
    float required_depth <- tonnage / 200;
    bool is_waiting <- false;
    bool is_loading <- false;
    bool is_unloading <- false;
    bool needs_loading <- false;  // Les bateaux n'ont pas besoin d'être chargés initialement
    bool is_registered <- false;
    point target;
    int loading_time <- rnd(20, 50);
    int current_loading_time <- 0;
    Parking_Space assigned_space <- nil;
    bool is_empty <- false;  // Tous les bateaux arrivent pleins
    point initial_location;
    bool is_leaving <- false;
    
    init {
        location <- any_point_in(first(Water_Body).shape);
        initial_location <- copy(location);
        target <- port_entrance;
        write "Bateau " + name + " créé à " + location + " - Statut: chargé";
    }
    
    // Navigation avec contrainte sur l'eau
    reflex move when: target != nil and !is_loading and !is_unloading and !is_waiting {
        do goto target: target speed: speed on: water_area;
        
        if (location distance_to target < speed) {
            if (is_leaving) {
                do die;
            } else if (!is_registered) {
                ask first(Control_Center) {
                    myself.is_registered <- true;
                    do process_boat(myself);
                }
            } else if (assigned_space != nil) {
                if (!is_empty) {  // Comme le bateau est plein, on commence par le déchargement
                    is_unloading <- true;
                    needs_loading <- true;
                    write name + " commence le déchargement";
                }
            }
        }
    }
    
    // Représentation visuelle avec distinction chargement/déchargement
    aspect default {
        draw boat_image size: 0.001;
        
        // Indicateur d'état
        point status_pos <- location;
        draw circle(0.00005) color: is_empty ? #yellow : #blue at: status_pos;
        
        // Numérotation des bateaux
        //draw string(name) at: location + {0, 0.002} color: #black font: font("Arial", 10, #bold);
    }
    
    // Amélioration du chargement/déchargement
    reflex handle_cargo_operation when: is_loading or is_unloading {
        current_loading_time <- current_loading_time + 1;
        if (current_loading_time >= loading_time) {
            if (is_unloading) {
                is_unloading <- false;
                is_empty <- true;
                current_loading_time <- 0;
                write name + " a terminé le déchargement, préparation pour le chargement";
                if (needs_loading) {
                    is_loading <- true;
                }
            } else if (is_loading) {
                is_loading <- false;
                is_empty <- false;
                needs_loading <- false;
                current_loading_time <- 0;
                if (assigned_space != nil) {
                    assigned_space.is_occupied <- false;
                    assigned_space <- nil;
                }
                is_leaving <- true;
                target <- world.find_exit_point(location);
                write name + " a terminé le cycle complet et quitte le port vers " + target;
            }
        }
    }
    
    // Vérification des conditions de marée
    reflex check_tide {
        is_waiting <- required_depth > current_tide_level;
    }
}

// Centre de contrôle du port
species Control_Center {
    list<Boat> waiting_boats <- [];  // File d'attente des bateaux
    
    aspect default {
        draw shape color: #green;
    }
    
    // Gestion des bateaux en attente
    reflex manage_waiting_boats {
        list<Parking_Space> available <- Parking_Space where (!each.is_occupied);
        if (!empty(available) and !empty(waiting_boats)) {
            list<Boat> boats_to_remove <- [];
            loop boat over: waiting_boats {
                Parking_Space space <- available first_with (each.depth >= boat.required_depth);
                if (space != nil and !space.is_occupied) {
                    do assign_space(boat, space);
                    add boat to: boats_to_remove;
                    write name + ": Espace attribué au bateau " + boat + " depuis la file d'attente";
                }
            }
            waiting_boats <- waiting_boats - boats_to_remove;
        }
    }
    
    // Traitement d'un nouveau bateau
    action process_boat(Boat boat) {
        list<Parking_Space> available <- Parking_Space where (!each.is_occupied);
        if (!empty(available)) {
            Parking_Space space <- available first_with (each.depth >= boat.required_depth);
            if (space != nil) {
                do assign_space(boat, space);
            } else {
                add boat to: waiting_boats;
                point wait_point <- any_point_in(water_area);  // Point d'attente dans l'eau
                boat.target <- wait_point;
                write name + ": Pas d'espace disponible pour " + boat + " - Ajouté à la file d'attente";
            }
        } else {
            add boat to: waiting_boats;
            point wait_point <- any_point_in(water_area);  // Point d'attente dans l'eau
            boat.target <- wait_point;
            write name + ": Pas d'espace disponible pour " + boat + " - Ajouté à la file d'attente";
        }
    }
    
    // Attribution d'un espace à un bateau
    action assign_space(Boat boat, Parking_Space space) {
        space.is_occupied <- true;
        boat.assigned_space <- space;
        boat.target <- space.location;
        write name + ": Attribution de l'espace " + space + " au bateau " + boat;
    }
}

// Espaces de stationnement
species Parking_Space {
    bool is_occupied <- false;
    float depth;
    
    aspect default {
        draw shape color: is_occupied ? #black : #gray;
    }
}

// Définition de l'expérience
experiment port_simulation type: gui {
    parameter "Nombre de bateaux" var: number_of_boats min: 3 max: 20;
    
    output {
        display main_display type: opengl {
            species Water_Body;
            species Control_Center;
            species Parking_Space;
            species Boat;
            
            graphics "Info" {
                draw "Marée: " + string(current_tide_level with_precision 2) + "m" 
                     at: {5, 5} color: #black font: font("Default", 16, #bold);
            }
        }
        
        // Moniteurs pour les statistiques principales
        monitor "Niveau de marée (m)" value: current_tide_level with_precision 2 color: #blue;
        monitor "Espaces disponibles" value: length(Parking_Space where (!each.is_occupied)) color: #gray;
//        monitor "Bateaux en attente" value: length(Boat where (each.is_waiting)) color: #orange;
        monitor "Bateaux en cours de chargement" value: Boat count (each.is_loading) color: #yellow;
        monitor "Bateaux en cours de déchargement" value: Boat count (each.is_unloading) color: #red;
        monitor "Total bateaux dans le port" value: length(Boat) color: #green;
        monitor "Bateaux bloqués par la marée" value: Boat count (each.required_depth > current_tide_level) color: #red;
        
        // Graphique de distribution des états des bateaux
//        display "État des Bateaux" {
//            chart "Distribution des états des bateaux" type: pie {
//                data "En attente" value: length(Boat where (each.is_waiting)) color: #orange;
//                data "En chargement" value: Boat count (each.is_loading) color: #yellow;
//                data "En déchargement" value: Boat count (each.is_unloading) color: #red;
//                data "En navigation" value: Boat count (!each.is_loading and !each.is_unloading and !each.is_waiting) color: #blue;
//            }
//        }
        
        // Graphique d'occupation des espaces de stationnement
//        display "Occupation des quais" {
//            chart "État des espaces de stationnement" type: pie {
//                data "Occupés" value: length(Parking_Space where (each.is_occupied)) color: #black;
//                data "Disponibles" value: length(Parking_Space where (!each.is_occupied)) color: #gray;
//            }
//        }
        
        // Graphique de l'évolution temporelle
//        display "Évolution temporelle" {
//            chart "Activité du port" type: series {
//                data "Niveau marée" value: current_tide_level color: #blue;
//                data "Bateaux en attente" value: length(Boat where (each.is_waiting)) color: #orange;
//                data "Espaces disponibles" value: length(Parking_Space where (!each.is_occupied)) color: #gray;
//            }
//        }
        
        // Graphique des profondeurs requises
//        display "Distribution des profondeurs" {
//            chart "Profondeurs requises par les bateaux" type: histogram {
//                data "0-2m" value: Boat count (each.required_depth <= 2) color: #green;
//                data "2-4m" value: Boat count (each.required_depth > 2 and each.required_depth <= 4) color: #yellow;
//                data "4-6m" value: Boat count (each.required_depth > 4 and each.required_depth <= 6) color: #orange;
//                data ">6m" value: Boat count (each.required_depth > 6) color: #red;
//            }
//        }
    }
} 