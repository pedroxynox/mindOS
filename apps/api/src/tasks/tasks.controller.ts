import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser, JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateTaskDto } from './dto/create-task.dto';
import { UpdateTaskDto } from './dto/update-task.dto';
import { TaskResponse } from './tasks.mapper';
import { TasksService } from './tasks.service';

/**
 * Task management endpoints (`/v1/tasks`). All require a Bearer token; the owner
 * comes from the token, never the request.
 */
@UseGuards(JwtAuthGuard)
@Controller('tasks')
export class TasksController {
  constructor(private readonly tasks: TasksService) {}

  /** List tasks ordered by priority. `?filter=pending` hides completed ones. */
  @Get()
  list(
    @CurrentUser() user: AuthenticatedUser,
    @Query('filter') filter?: string,
  ): Promise<TaskResponse[]> {
    return this.tasks.list(user.id, filter === 'pending' ? 'pending' : 'all');
  }

  @Post()
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateTaskDto,
  ): Promise<TaskResponse> {
    return this.tasks.create(user.id, dto);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateTaskDto,
  ): Promise<TaskResponse> {
    return this.tasks.update(user.id, id, dto);
  }
}
