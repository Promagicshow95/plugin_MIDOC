/**
* Name: GTFSreader
* Based on the internal empty template. 
* Author: benoitgaudou
* Tags: 
*/


model GTFSreader

global {
	gtfs_file hanoi_gtfs <- gtfs_file("../includes/hanoi_gtfs_am");
	
//	geometry shape <- envelope(hanoi_gtfs);
	
	init {
		write hanoi_gtfs.contents;
		
//		create bus_stops;
	}
}

//species bus_stops parent: transport_stop {
//	
//}



experiment name type: gui {

	
	// Define parameters here if necessary
	// parameter "My parameter" category: "My parameters" var: one_global_attribute;
	
	// Define attributes, actions, a init section and behaviors if necessary
	// init { }
	
	
	output {
	// Define inspectors, browsers and displays here
	
	// inspect one_or_several_agents;
	//
	// display "My display" { 
	//		species one_species;
	//		species another_species;
	// 		grid a_grid;
	// 		...
	// }

	}
}