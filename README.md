

TODO: check if the following is handled and how. it might be better to have a vessel wait, so that the ports inventory hints a certain level. Does the heuristic handles this, if not maybe wise to have it handled
TODO: Also it is not handled to choose alpha in a certain way, like maybe inventory in the next port would be fucked, but in the current one its fine with alpha = 0, but why not have alpha non-zero now if in the next port P costs are high, maybe greedily choosen based on which port has low P (inventory) costs
TODO: consider carefully when to use copy() or deepcopy()
TODO: vessel discount_empty() is not handled, so it might happen that vessel goes empty somewhere adn that gets a discount
TODO: How does the starting ports handled? Routing costs, or there is an initial port? 
TODO: It would be wise to precalculate C_{a}^vc and P_{j,t}
TODO: Handle efficiency and speed with highly nested variables
TODO: What is last_service_time_vessel for?
TODO: Pay extra attention how to handle nothing variables for last_occ_...
TODO: There might be initial inventory levels at ports and even in vessels
TODO: in the mrplib there is this mindurationinregiontable, what is that?