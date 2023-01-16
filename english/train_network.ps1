# https://github.com/cloneofsimo/lora
# https://github.com/kohya-ss/sd-scripts
# https://rentry.org/2chAI_LoRA_Dreambooth_guide_english

##### Config start #####

# Path variables
$sd_scripts_dir = "X:\git-repos\sd-scripts\" # Path to kohya-ss/sd-scripts repository 
$ckpt = "X:\SD-models\checkpoint.safetensors" # Path to checkpoint (ckpt / safetensors)
$is_sd_v2_ckpt = 0 # '1' if loading SD 2.x ckeckpoint
$is_sd_v2_768_ckpt = 0 # '1', if loading SD 2.x-768 checkpoint
$image_dir = "X:\training_data\img\" # Path to training images folder
$reg_dir = "X:\training_data\img_reg\" # Path to regularization folder (path can lead to an empty folder, but folder must exist)
$output_dir = "X:\LoRA\" # LoRA network saving path
$output_name = "my_LoRA_network_v1" # LoRA network file name (no extension)
$use_vae = 0 # Use VAE for loaded checkpoint
$vae_path = "X:\SD-models\checkpoint.vae.pt" # Path to VAE

# Custom training time (optional)
$desired_training_time = 0 # If greater than 0, ignore number of images with repetitions when calculating training steps and train network for N minutes
$gpu_training_speed = "1.23it/s | 1.23s/it" # Average training speed, depending on GPU. Possible values are XX.XXit/s or XX.XXs/it

# Main variables
$train_batch_size = 1 # How much images to train simultaneously. Higher number = less training steps (faster), higher VRAM usage
$resolution = 512 # Training resolution (px)
$num_epochs = 10 # Number of epochs. Have no power if $desired_training_time > 0
$save_every_n_epochs = 1 # Save every n epochs
$save_last_n_epochs = 999 # Save only last n epochs
$max_token_length = 75 # Max token length. Possible values: 75 / 150 / 225
$clip_skip = 1 # https://github.com/AUTOMATIC1111/stable-diffusion-webui/wiki/Features#ignore-last-layers-of-clip-model

# Advanced variables
$learning_rate = 1e-4 # Learning rate
$unet_lr = $learning_rate # U-Net learning rate
$text_encoder_lr = $learning_rate # Text encoder learning rate
$scheduler = "cosine_with_restarts" # Scheduler to use for learning rate. Possible values: linear, cosine, cosine_with_restarts, polynomial, constant (default), constant_with_warmup
$lr_warmup_ratio = 0.0 # Ratio of warmup steps in the learning rate scheduler to total training steps (0 to 1)
$network_dim = 128 # Size of network. Higher number = higher accuracy, output file size and VRAM usage
$save_precision = "fp16" # Whether to use custom precision for saving, and its type. Possible values: no, float, fp16, bf16
$mixed_precision = "fp16" # Whether to use mixed precision for training, and its type. Possible values: no, fp16, bf16
$is_random_seed = 1 # Seed for training. 1 = random seed, 0 = static seed
$shuffle_caption = 1 # Shuffle comma-separated captions
$keep_tokens = 0 # Keep heading N tokens when shuffling caption tokens
$do_not_interrupt = 0 # Do not interrupt script on questionable moments

# Logging and debug
$logging_enabled = 0
$logging_dir = "X:\LoRA\logs\"
$log_prefix = $output_name
$debug_dataset = 0
$test_run = 0 # Do not launch main script

##### Config end #####

function Is-Numeric ($value) { return $value -match "^[\d\.]+$" }

function Write-ColorOutput($ForegroundColor)
{
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) { Write-Output $args }
    else { $input | Write-Output }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-Output "Calculating number of images in folders"
$total = 0
$is_structure_wrong = 0
$abort_script = 0
$iter = 0

Get-ChildItem -Path $image_dir -Directory | ForEach-Object {
    $parts = $_.Name.Split("_")
    if (!(Is-Numeric $parts[0]))
    {
		Write-ColorOutput red "Error in $($_):`n`t$($parts[0]) is not a number"
		$is_structure_wrong = 1
        return
    }
	if ([int]$parts[0] -le 0)
	{
		Write-ColorOutput red "Error in $($_):`nNumber of repeats in folder name must be >0"
		$is_structure_wrong = 1
        return
	}
    $repeats = [int]$parts[0]
    $imgs = Get-ChildItem $_.FullName -Depth 0 -File -Include *.jpg, *.png, *.webp | Measure-Object | ForEach-Object { $_.Count }
	if ($iter -eq 0) { Write-Output "Training images:" }
    $img_repeats = ($repeats * $imgs)
    Write-Output "`t$($parts[1]): $repeats repeats * $imgs images = $($img_repeats)"
    $total += $img_repeats
	$iter += 1
}

$iter = 0

if ($is_structure_wrong -eq 0) { Get-ChildItem -Path $reg_dir -Directory | % { if ($abort_script -ne "n") { ForEach-Object {
    $parts = $_.Name.Split("_")
    if (!(Is-Numeric $parts[0]))
    {
		Write-ColorOutput red "Error in $($_):`n`t$($parts[0]) is not a number"
		$is_structure_wrong = 1
        return
    }
	if ([int]$parts[0] -le 0)
	{
		Write-ColorOutput red "Error in $($_):`nNumber of repeats in folder name must be >0"
		$is_structure_wrong = 1
        return
	}
    $repeats = [int]$parts[0]
    $reg_imgs = Get-ChildItem $_.FullName -Depth 0 -File -Include *.jpg, *.png, *.webp | Measure-Object | ForEach-Object { $_.Count }
	if ($iter -eq 0) { Write-Output "Regularization images:" }
	if ($do_not_interrupt -le 0) { if ($reg_imgs -eq 0)
	{
		Write-ColorOutput darkyellow "Warning: regularization images folder exists, but is empty"
		do { $abort_script = Read-Host "Abort script? (y/N)" }
		until ($abort_script -eq "y" -or $abort_script -ceq "N")
		return
	} }
	else
	{
		$img_repeats = ($repeats * $reg_imgs)
		Write-Output "`t$($parts[1]): $repeats repeats * $reg_imgs images = $($img_repeats)"
		$iter += 1
	}
} } } }

if ($is_structure_wrong -eq 0 -and ($abort_script -eq "n" -or $abort_script -eq 0))
{
	Write-Output "Image number with repeats: $total"
	
	if ($desired_training_time -gt 0) 
	{
		if ($gpu_training_speed -match '\d+[.]\d+it[\/\\]s' -or $gpu_training_speed -match '\d+[.]\d+s[\/\\]it')
		{
			Write-Output "Using desired_training_time for calculation of training steps, considering the speed of the GPU"
			$speed_value = $gpu_training_speed -replace '[^.0-9]'
			if ([regex]::split($gpu_training_speed, '[\/\\]') -replace '\d+.\d+' -eq 's') { $speed_value = 1 / $speed_value }
			$max_train_steps = [float]$speed_value * 60 * $desired_training_time
			if ($reg_imgs -gt 0)
			{
				$max_train_steps *= 2
				$max_train_steps = [int]([math]::Round($max_train_steps))
				Write-Output "Number of regularization images greater than 0"
				if ($do_not_interrupt -le 0) { do { $reg_img_compensate_time = Read-Host "Would you like to halve the number of training steps to make up for the increased time? (y/N)" }
				until ($reg_img_compensate_time -eq "y" -or $reg_img_compensate_time -ceq "N") }
				if ($reg_img_compensate_time -eq "y")
				{
					$max_train_steps = [int]([math]::Round($max_train_steps / 2))
					Write-Output "Total training steps: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time minute(-s) ≈ $max_train_steps training step(-s)"
				}
				else
				{
					Write-Output "Your choice is no. Increased time will not be compensated, duration of training is doubled"
					Write-Output "Total training steps: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time minute(-s) * 2 ≈ $max_train_steps training step(-s)"
				}
			}
		}
		else
		{
			Write-ColorOutput red "The learning rate is incorrect in gpu_training_speed variable!"
			$abort_script = 1
		}
	}
	else
	{
		Write-Output "Using number of training images to calculate total training steps"
		Write-Output "Training batch size: $train_batch_size"
		Write-Output "Number of epochs: $num_epochs"
		if ($reg_imgs -gt 0)
		{
			$total *= 2
			Write-Output "Total train steps doubled: number of regularization images is greater than 0"
		}
		$max_train_steps = [int]($total / $train_batch_size * $num_epochs)
		Write-Output "Total training steps: $total / $train_batch_size * $num_epochs = $max_train_steps"
	}
	
	if ($is_random_seed -le 0) { $seed = 1337 }
	else { $seed = Get-Random }
	
	if ($lr_warmup_ratio -lt 0.0) { $lr_warmup_ratio = 0.0 }
	if ($lr_warmup_ratio -gt 1.0) { $lr_warmup_ratio = 1.0 }
	$lr_warmup_steps = [int]([math]::Round($max_train_steps * $lr_warmup_ratio))
	
	$image_dir = $image_dir.TrimEnd("\", "/")
	$reg_dir = $reg_dir.TrimEnd("\", "/")
	$output_dir = $output_dir.TrimEnd("\", "/")
	$logging_dir = $logging_dir.TrimEnd("\", "/")
	
	$run_parameters = "--network_module=networks.lora --pretrained_model_name_or_path=`"$ckpt`" --train_data_dir=`"$image_dir`" --reg_data_dir=`"$reg_dir`" --output_dir=`"$output_dir`" --output_name=`"$output_name`" --caption_extension=`".txt`" --resolution=$resolution --prior_loss_weight=1 --enable_bucket --min_bucket_reso=256 --max_bucket_reso=1024 --train_batch_size=$train_batch_size --lr_warmup_steps=$lr_warmup_steps --learning_rate=$learning_rate --unet_lr=$unet_lr --text_encoder_lr=$text_encoder_lr --max_train_steps=$([int]$max_train_steps) --use_8bit_adam --xformers --save_every_n_epochs=$save_every_n_epochs --save_last_n_epochs=$save_last_n_epochs --save_model_as=safetensors --keep_tokens=$keep_tokens --clip_skip=$clip_skip --seed=$seed --network_dim=$network_dim --cache_latents --lr_scheduler=$scheduler"
	
	if ($max_token_length -eq 75) { }
	else
	{
		if ($max_token_length -eq 150 -or $max_token_length -eq 225) { $run_parameters += " --max_token_length=$($max_token_length)" }
		else { Write-ColorOutput darkyellow "The max_token_length is incorrect! Use value 75" }
	}
	
	if ($shuffle_caption -ge 1) { $run_parameters += " --shuffle_caption" }
	if ($logging_enabled -ge 1) { $run_parameters += " --logging_dir=`"$logging_dir`" --log_prefix=`"$output_name`""}
	if ($use_vae -ge 1) { $run_parameters += " --vae=`"$vae_path`"" }
	if ($mixed_precision -eq "fp16" -or $mixed_precision -eq "bf16") { $run_parameters += " --mixed_precision=$mixed_precision" }
	if ($save_precision -eq "float" -or $save_precision -eq "fp16" -or $save_precision -eq "bf16") { $run_parameters += " --save_precision=$save_precision" }
	if ($debug_dataset -ge 1) { $run_parameters += " --debug_dataset"}
	
	if ($abort_script -eq "n" -or $abort_script -eq 0)
	{
		if ($is_sd_v2_ckpt -le 0) { Write-Output "Stable Diffusion 1.x checkpoint" }
		if ($is_sd_v2_ckpt -ge 1)
		{
			if ($is_sd_v2_768_ckpt -ge 1)
			{
				$v2_resolution = "768"
				$run_parameters += " --v_parameterization"
			}
			else { $v2_resolution = "512" }
			Write-Output "Stable Diffusion 2.x ($v2_resolution) checkpoint"
			$run_parameters += " --v2"
			if ($clip_skip -eq -not 1 -and $do_not_interrupt -le 0)
			{
				Write-ColorOutput darkyellow "Warning: training results of SD 2.x checkpoint with clip_skip other than 1 might be unpredictable"
				do { $abort_script = Read-Host "Abort script? (y/N)" }
				until ($abort_script -eq "y" -or $abort_script -ceq "N")
			}
		}
	}
	
	if ($abort_script -eq "n" -or $abort_script -eq 0)
	{
		sleep -s 1
		Write-ColorOutput green "Running script with parameters:"
		sleep -s 1
		Write-Output "$($run_parameters -split '--' | foreach { if ($_ -ceq '') { Write-Output '' } else { Write-Output --`"$_`n`" } } | foreach { $_ -replace '=', ' = ' })"
		if ($test_run -le 0)
		{
			$script_origin = (get-location).path
			cd $sd_scripts_dir
			.\venv\Scripts\activate
			powershell accelerate launch --num_cpu_threads_per_process 12 train_network.py $run_parameters
			deactivate
			cd $script_origin
		}
	}
}
#v0.9