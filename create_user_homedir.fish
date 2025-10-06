#!/run/current-system/sw/bin/fish

if test (count $argv) -ne 1
    echo "Usage create_user_homedir.fish <user_name>"
end

set user_name $argv[1]
set user_dir "/home/$user_name"
set user_fish_dir "$user_dir/.config/fish"
set user_readme "$user_dir/README.md"


echo "Creating user dir @ $user_dir"
sudo mkdir $user_dir
sudo chown $user_name:users $user_dir

echo "Copying fish aliases and functions to $user_fish_dir"
sudo cp -r ~/.config/fish/functions $user_fish_dir
sudo chown -R $user_name:users "$user_fish_dir/functions"
sudo cp -r ~/.config/fish/config.fish $user_fish_dir
sudo chown -R $user_name:users "$user_fish_dir/config.fish"

echo "Creating $user_readme"
sudo cp new_user_readme.md $user_readme
sudo chown -R $user_name:users $user_readme

echo "All done!"
