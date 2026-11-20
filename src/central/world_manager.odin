/*

    World manager is a great name!

    The purpose of the world manager is to provide a way to list, fetch, create worlds and
    get their properties. Closely related to *The World Forge*.
    
    It knows which worlds are servers and which are local saves. 

*/

package central;



WorldEntry :: struct {
    name: string,

    path: string,
    address: string, // "ip_address:port"

}


WorldManager :: struct {

    worldEntries: [dynamic]WorldEntry,

}

