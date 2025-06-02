
/**
* Name: Test
* Based on the internal empty template. 
* Author: dung
* Tags: 
*/


model Test

/* Insert your model definition here */

global {

    shape_file stops0_shape_file <- shape_file("../../includes/stops_points_wgs84.shp");
    
    geometry shape <- envelope(stops0_shape_file);
    
    init {
        create stop from: stops0_shape_file;
    }

}

species stop {
    // attributes
    string stop_name;
    string stop_id;
    float route_type;
    float width <- 100.0;
    
    
    aspect default {
        
        draw circle(24) + width color: #black;
        draw circle(22) + width color: #yellow;
    }
}

experiment e type: gui {
    output {
        display map {
            species stop;
        }
    }
}
