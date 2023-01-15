# https://github.com/cloneofsimo/lora
# https://github.com/kohya-ss/sd-scripts
# https://rentry.org/2chAI_LoRA_Dreambooth_guide

##### Начало конфига #####

# Директории
$sd_scripts_dir = "X:\git-repos\sd-scripts\" # Путь к папке с репозиторием kohya-ss/sd-scripts
$ckpt = "X:\SD-models\checkpoint.safetensors" # Путь к чекпоинту (ckpt / safetensors)
$is_sd_v2_ckpt = 0 # Поставь '1' если загружаешь SD 2.x чекпоинт
$is_sd_v2_768_ckpt = 0 # Также поставь здесь значение '1', если загружаешь SD 2.x-768 чекпоинт
$image_dir = "X:\training_data\img\" # Путь к папке с изображениями
$reg_dir = "X:\training_data\img_reg\" # Путь к папке с регуляризационными изображениями (можно указать на пустую папку, но путь обязательно должен быть указан)
$output_dir = "X:\LoRA\" # Директория сохранения LoRA чекпоинтов
$output_name = "my_LoRA_network_v1" # Название файла (расширение не нужно)
$use_vae = 0 # Использовать ли VAE для загружаемого чекпоинта
$vae_path = "X:\SD-models\checkpoint.vae.pt" # Путь к VAE

# Время тренировки (опционально)
$desired_training_time = 0 # Если значение выше 0, игнорировать количество изображений с повторениями при вычислении количества шагов и обучать сеть в течении N минут.
$gpu_training_speed = "1.23it/s | 1.23s/it" # Средняя скорость тренировки, учитывая мощность GPU. Значение вида XX.XXit/s или XX.XXs/it

# Основные переменные
$train_batch_size = 1 # Количество изображений, на которых идёт обучение, одновременно. Чем больше значение, тем меньше шагов обучения (обучение проходит быстрее), но больше потребление видеопамяти
$resolution = 512 # Разрешение обучения (пиксели)
$num_epochs = 10 # Число эпох. Не имеет силы при $desired_training_time > 0
$save_every_n_epochs = 1 # Сохранять чекпоинт каждые N эпох
$save_last_n_epochs = 999 # Сохранить только последние N эпох
$max_token_length = 75 # Максимальная длина токена. Возможные значения: 75 / 150 / 225
$clip_skip = 1 # https://github.com/AUTOMATIC1111/stable-diffusion-webui/wiki/Features#ignore-last-layers-of-clip-model

# Дополнительные переменные
$learning_rate = 1e-4 # Скорость обучения
$unet_lr = $learning_rate # Скорость обучения U-Net
$text_encoder_lr = $learning_rate # Скорость обучения текстового энкодера
$scheduler = "cosine_with_restarts" # Планировщик скорости обучения. Возможные значения: linear, cosine, cosine_with_restarts, polynomial, constant (по умолчанию), constant_with_warmup
$lr_warmup_ratio = 0.0 # Отношение количества шагов разогрева планировщика к количеству шагов обучения (от 0 до 1)
$network_dim = 128 # Размер нетворка. Чем больше значение, тем больше точность и размер выходного файла
$save_precision = "fp16" # Использовать ли пользовательскую точность сохранения, и её тип. Возможные значения: no, float, fp16, bf16
$mixed_precision = "fp16" # Использовать ли смешанную точность для обучения, и её тип. Возможные значения: no, fp16, bf16
$is_random_seed = 1 # Сид обучения. 1 = рандомный сид, 0 = статичный
$shuffle_caption = 1 # Перетасовывать ли теги в файлах описания, разделённых запятой
$keep_tokens = 0 # Не перетасовывать первые N токенов при перемешивании описаний
$do_not_interrupt = 0 # Не прерывать работу скрипта вопросами

# Логгирование и дебаг
$logging_enabled = 0
$logging_dir = "X:\LoRA\logs\"
$log_prefix = $output_name
$debug_dataset = 0
$test_run = 0 # Не запускать основной скрипт

##### Конец конфига #####

function Is-Numeric ($value) { return $value -match "^[\d\.]+$" }

function Write-ColorOutput($ForegroundColor)
{
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) { Write-Output $args }
    else { $input | Write-Output }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Word-Ending($value)
{
	$ending = $value.ToString()
	if ($ending -ge "11" -and $ending -le "19") { return "й" }
	$ending = $ending.Substring([Math]::Max($ending.Length, 0) - 1)
	if ($ending -eq "1") { return "е" }
	if ($ending -ge "2" -and $ending -le "4") { return "я" }
	if (($ending -ge "5" -and $ending -le "9") -or $ending -eq "0") { return "й" }
}

Write-Output "Подсчет количества изображений в папках"
$total = 0
$is_structure_wrong = 0
$abort_script = 0
$iter = 0

Get-ChildItem -Path $image_dir -Directory | ForEach-Object {
    $parts = $_.Name.Split("_")
    if (!(Is-Numeric $parts[0]))
    {
		Write-ColorOutput red "Ошибка в $($_):`n`t$($parts[0]) не является числом"
		$is_structure_wrong = 1
        return
    }
	if ([int]$parts[0] -le 0)
	{
		Write-ColorOutput red "Ошибка в $($_):`nПовторения в имени папки с изображениями должно быть >0"
		$is_structure_wrong = 1
        return
	}
    $repeats = [int]$parts[0]
    $imgs = Get-ChildItem $_.FullName -Depth 0 -File -Include *.jpg, *.png, *.webp | Measure-Object | ForEach-Object { $_.Count }
	if ($iter -eq 0) { Write-Output "Обучающие изображения:" }
    $img_repeats = ($repeats * $imgs)
    Write-Output "`t$($parts[1]): $repeats повторени$(Word-Ending $repeats) * $imgs изображени$(Word-Ending $imgs) = $($img_repeats)"
    $total += $img_repeats
	$iter += 1
}

$iter = 0

if ($is_structure_wrong -eq 0) { Get-ChildItem -Path $reg_dir -Directory | % { if ($abort_script -ne "n") { ForEach-Object {
    $parts = $_.Name.Split("_")
    if (!(Is-Numeric $parts[0]))
    {
		Write-ColorOutput red "Ошибка в $($_):`n`t$($parts[0]) не является числом"
		$is_structure_wrong = 1
        return
    }
	if ([int]$parts[0] -le 0)
	{
		Write-ColorOutput red "Ошибка в $($_):`nПовторения в имени папки с изображениями должно быть >0"
		$is_structure_wrong = 1
        return
	}
    $repeats = [int]$parts[0]
    $reg_imgs = Get-ChildItem $_.FullName -Depth 0 -File -Include *.jpg, *.png, *.webp | Measure-Object | ForEach-Object { $_.Count }
	if ($iter -eq 0) { Write-Output "Регуляризационные изображения:" }
	if ($do_not_interrupt -le 0) { if ($reg_imgs -eq 0)
	{
		Write-ColorOutput darkyellow "Внимание: папка для регуляризационных изображений присутствует, но в ней ничего нет"
		do { $abort_script = Read-Host "Прервать выполнение скрипта? (y/N)" }
		until ($abort_script -eq "y" -or $abort_script -ceq "N")
		return
	} }
	else
	{
		$img_repeats = ($repeats * $reg_imgs)
		Write-Output "`t$($parts[1]): $repeats повторени$(Word-Ending $repeats) * $reg_imgs изображени$(Word-Ending $reg_imgs) = $($img_repeats)"
		$iter += 1
	}
} } } }

if ($is_structure_wrong -eq 0 -and ($abort_script -eq "n" -or $abort_script -eq 0))
{
	
	Write-Output "Количество обучающих изображений с повторениями: $total"
	
	if ($desired_training_time -gt 0) 
	{
		if ($gpu_training_speed -match '\d+[.]\d+it[\/\\]s' -or $gpu_training_speed -match '\d+[.]\d+s[\/\\]it')
		{
			Write-Output "Используем desired_training_time для вычисления шагов обучения, учитывая скорость GPU"
			$speed_value = $gpu_training_speed -replace '[^.0-9]'
			if ([regex]::split($gpu_training_speed, '[\/\\]') -replace '\d+.\d+' -eq 's') { $speed_value = 1 / $speed_value }
			$max_train_steps = [float]$speed_value * 60 * $desired_training_time
			if ($reg_imgs -gt 0)
			{
				$max_train_steps *= 2
				$max_train_steps = [math]::Round($max_train_steps)
				Write-Output "Количество регуляризационных изображений больше 0"
				if ($do_not_interrupt -le 0) { do { $reg_img_compensate_time = Read-Host "Вы хотите уменьшить количество шагов вдвое для компенсации увеличенного времени? (y/N)" }
				until ($reg_img_compensate_time -eq "y" -or $reg_img_compensate_time -ceq "N") }
				if ($reg_img_compensate_time -eq "y" -or $do_not_interrupt -ge 1)
				{
					[int]$max_train_steps = [math]::Round($max_train_steps / 2)
					Write-Output "Количество шагов: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time минут(-а) ≈ $max_train_steps шаг(-ов)"
				}
				else
				{
					Write-Output "Вы выбрали нет. Увеличенное время компенсировано не будет, длительность тренировки увеличена вдвое"
					Write-Output "Количество шагов: $([math]::Round($($speed_value * 60), 2)) it/min * $desired_training_time минут(-а) * 2 ≈ $max_train_steps шаг(-ов)"
				}
			}
		}
		else
		{
			Write-ColorOutput red "Неверно указана скорость обучения gpu_training_speed!"
			$abort_script = 1
		}
	}
	else
	{
		Write-Output "Используем количество изображений для вычисления шагов обучения"
		Write-Output "Количество эпох: $num_epochs"
		Write-Output "Размер обучающей партии (train_batch_size): $train_batch_size"
		if ($reg_imgs -gt 0)
		{
			$total *= 2
			Write-Output "Количество регуляризационных изображений больше 0: количество шагов будет увеличено вдвое"
		}
		$max_train_steps = [int]($total / $train_batch_size * $num_epochs)
		Write-Output "Количество шагов: $total / $train_batch_size * $num_epochs = $max_train_steps"
	}
	
	if ($is_random_seed -le 0) { $seed = 1337 }
	else { $seed = Get-Random }
	
	if ($lr_warmup_ratio -lt 0.0) { $lr_warmup_ratio = 0.0 }
	if ($lr_warmup_ratio -gt 1.0) { $lr_warmup_ratio = 1.0 }
	$lr_warmup_steps = [math]::Round($max_train_steps * $lr_warmup_ratio)
	
	$image_dir = $image_dir.TrimEnd("\", "/")
	$reg_dir = $reg_dir.TrimEnd("\", "/")
	$output_dir = $output_dir.TrimEnd("\", "/")
	$logging_dir = $logging_dir.TrimEnd("\", "/")
	
	$run_parameters = "--network_module=networks.lora --pretrained_model_name_or_path=`"$ckpt`" --train_data_dir=`"$image_dir`" --reg_data_dir=`"$reg_dir`" --output_dir=`"$output_dir`" --output_name=`"$output_name`" --caption_extension=`".txt`" --resolution=$resolution --prior_loss_weight=1 --enable_bucket --min_bucket_reso=256 --max_bucket_reso=1024 --train_batch_size=$train_batch_size --lr_warmup_steps=$lr_warmup_steps --learning_rate=$learning_rate --unet_lr=$unet_lr --text_encoder_lr=$text_encoder_lr --max_train_steps=$max_train_steps --use_8bit_adam --xformers --save_every_n_epochs=$save_every_n_epochs --save_last_n_epochs=$save_last_n_epochs --save_model_as=safetensors --keep_tokens=$keep_tokens --clip_skip=$clip_skip --seed=$seed --network_dim=$network_dim --cache_latents --lr_scheduler=$scheduler"
	
	if ($max_token_length -eq 75) { }
	else
	{
		if ($max_token_length -eq 150 -or $max_token_length -eq 225) { $run_parameters += " --max_token_length=$($max_token_length)" }
		else { Write-ColorOutput darkyellow "Неверно указан max_token_length! Используем значение 75" }
	}
	
	if ($shuffle_caption -ge 1) { $run_parameters += " --shuffle_caption" }
	if ($logging_enabled -ge 1) { $run_parameters += " --logging_dir=`"$logging_dir`" --log_prefix=`"$output_name`""}
	if ($use_vae -ge 1) { $run_parameters += " --vae=`"$vae_path`"" }
	if ($mixed_precision -eq "fp16" -or $mixed_precision -eq "bf16") { $run_parameters += " --mixed_precision=$mixed_precision" }
	if ($save_precision -eq "float" -or $save_precision -eq "fp16" -or $save_precision -eq "bf16") { $run_parameters += " --save_precision=$save_precision" }
	if ($debug_dataset -ge 1) { $run_parameters += " --debug_dataset"}
	
	if ($abort_script -eq "n" -or $abort_script -eq 0)
	{
		if ($is_sd_v2_ckpt -le 0) { Write-Output "Stable Diffusion 1.x чекпоинт" }
		if ($is_sd_v2_ckpt -ge 1)
		{
			if ($is_sd_v2_768_ckpt -ge 1)
			{
				$v2_resolution = "768"
				$run_parameters += " --v_parameterization"
			}
			else { $v2_resolution = "512" }
			Write-Output "Stable Diffusion 2.x ($v2_resolution) чекпоинт"
			$run_parameters += " --v2"
			if ($clip_skip -eq -not 1 -and $do_not_interrupt -le 0)
			{
				Write-ColorOutput darkyellow "Внимание: результаты обучения SD 2.x чекпоинта с clip_skip отличным от 1 могут быть непредсказуемые"
				do { $abort_script = Read-Host "Прервать выполнение скрипта? (y/N)" }
				until ($abort_script -eq "y" -or $abort_script -ceq "N")
			}
		}
	}
	
	if ($abort_script -eq "n" -or $abort_script -eq 0)
	{
		sleep -s 1
		Write-ColorOutput green "Выполнение скрипта с параметрами:"
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

#ver=0.9