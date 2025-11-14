# Return the power set of the given list
def power_set(input_list):
    # Initialize the power set with the empty set
    all_subsets = [[]]

    # Iterate over each element in the input list
    for element in input_list:
        # Create new subsets by adding the current element to existing subsets
        new_subsets = []
        for subset in all_subsets:
            new_subsets.append(subset + [element])
        # Add the newly created subsets to the total collection
        all_subsets.extend(new_subsets)

    return all_subsets