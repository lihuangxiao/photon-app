I want to create a mobile APP, that runs on both adriod and IOS (we can start with IOS first but leave planning for android later)          

the APP goes through all the photos locally, and help user with 1 goal in mind: identify photos that can be deleted, in the most efficient and user friendly way.
Possible criterias to evaluate(I'm putting this down here as a start, we might need to re-evaludate this):
- If it is pretty obvious that there is a lot of "useless photos", can our workflow quickly identify them, and prompt user for deletion very quickly (without asking users a ton of other questions that are not relevant to these)
- workflow should be safe, we should ask user confirmation before delete anything
- overall, less effort for deleting photos, we can do stage by stage, we don't need to figure out all deletion at the start, the workflow should be friendly to users (especially new users), for return users we can have extra workflow that we can worry about in the future.

--------------------------------

I have a proposed workflow:                                                                                                                 
1, we want to firstly ask user to understand, very roughly, how many photos they would like to delete. I don't know how exactly this information will be used, but if user is willing to provide this information, I imagine we can use this to adjust our workflow accordingly


2, guessing round 1: we want to categorize photos into different categories. How categories are predicted can be different for different scenarios, but we want to be able to assign different "likely to delete" scores for each categories.
the goal is not to simply categoris cat photos with cat photos, building photos with building photos.
the goal is to be able to be able to put more photos in categories with high likely to delete scores.

Let me start with an example.
If a user's day to day activity (mobile games, or work, or social habits) makes it such that the person takes a certain type of screenshots a lot every day, then we want to identify this, and group all of those similar screenshots together, and assign a high likely to delete score
If a user likes travelling a lot, and has a lot of photos from different places, some are buildings, some are scenes, some are food, then group all of them together and assigning them very low scores would be reasonable at this stage. We can always deal with them later.

At this stage, it is okay to have a bunch of photos in "not sure" category, we want to be able to identify highly likely to be deleted photos in chunks, and deal with them immediately after this stage

There should be some UI magic that shows people that we are doing this right now.

3, After guessing round 1 is completed, trigger different experiences based on our result.

3.1, we found at least 1 category of "highly likely to be deleted photos": 
3.1.1 tell user, hey good news, we found some possible candidates for deletion.
3.1.2 Then randomly pick a couple of photos and ask user to choose yes/no for whether they want to delete.
3.1.3, if user picked "yes" for all of those random picks, tell user more about the "cateogry", explain why we grouped them together, and ask for permission to proceed with deletion 
3.1.4, if user picked "no" for all of those random picks, proceed to next category
3.1.5, if user response is mixed of yes/no, ask user whether or not they want to further categorize these photos (figure out a way to ask nicely, make sure the question makes sense, we might want to briefly talk about the current category, how it's being grouped)

3.2, if there are no categories of "highly likely to be deleted photos" (either none to begin with, or we have exhausted 3.1), then we can either:
3.2.1: ask user for ideas on what kind of photos to delete
3.2.2: proceed with "medium likely to be deleted photos"
3.2.3: enter guessing round 1: aim for smaller size categories, try to produce higher likely to proceed 

------------------------------------------------------------------------------------

obviously, this will be a fairly large project. we will need to:
- figure out how to integrate with AI functionality to do the understanding of photos/guessing/explaning/processing user additional input, etc.
- need to keep cost low
- need to be very safe, to avoid deleting user photos when they arn't expecting
- need great UI design
- need to pubslih APP
- need to host the APP (maybe we would need a Backend)
- is there a way we can protect someone else to easily copy our stuff?
